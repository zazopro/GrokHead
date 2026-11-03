import Darwin
import Foundation

enum HeadState: String {
    case idle
    case working
    case stale
    case done
    case error
}

struct TaskFlagPayload: Codable {
    let id: String?
    let title: String?
    let status: String?
    let progress: Double?
    let time: String?
}

struct TrackedTask {
    let id: String
    var title: String
    var status: HeadState
    var progress: Double?
    var updatedAt: Date
    var formattedTime: String
    var acknowledged: Bool
}

struct WatcherSnapshot {
    let aggregateState: HeadState
    let badgeCount: Int
    let activeProgress: Double?
    let subtitle: String?
}

final class TaskWatcher {
    var onSnapshotChanged: ((WatcherSnapshot) -> Void)?

    private let settings: AppSettings
    private let notifier: SoundAndNotifier
    private let queue = DispatchQueue(label: "com.grokhead.taskwatcher", qos: .utility)

    private var tasksById: [String: TrackedTask] = [:]
    private var orderedIds: [String] = []

    private var folderDescriptor: CInt = -1
    private var fsSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var staleAndCleanupTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastArchiveCleanupDate: Date = .distantPast

    init(settings: AppSettings, notifier: SoundAndNotifier) {
        self.settings = settings
        self.notifier = notifier
    }

    func start() {
        queue.async { [weak self] in
            self?.ensureDirectoriesExist()
            self?.cleanupArchiveOlderThan7DaysIfNeeded(force: true)
            self?.attachFileSystemWatcher()
            self?.startPollTimer()
            self?.startStaleAndCleanupTimer()
            self?.scanWatchFolder()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.teardownWatchers()
        }
    }

    func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.teardownWatchers()
            self.ensureDirectoriesExist()
            self.attachFileSystemWatcher()
            self.startPollTimer()
            self.startStaleAndCleanupTimer()
            self.scanWatchFolder()
        }
    }

    // MARK: - URL Scheme Ingestion: grokhead://working?id=t1&title=Build&progress=0.5

    func handleIncomingURL(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let action = (url.host ?? comps.path.replacingOccurrences(of: "/", with: "")).lowercased()

        if action == "reset" {
            resetAll()
            return
        }

        let queryItems = comps.queryItems ?? []
        let id = queryItems.first(where: { $0.name == "id" })?.value
        let title = queryItems.first(where: { $0.name == "title" })?.value ?? "Task"
        let progressVal = queryItems.first(where: { $0.name == "progress" })?.value.flatMap(Double.init)

        queue.async { [weak self] in
            self?.applyEvent(
                rawId: id,
                title: title,
                rawStatus: action,
                progress: progressVal
            )
        }
    }

    func acknowledgeCompletedAndErrors() {
        queue.async { [weak self] in
            guard let self else { return }
            for key in self.tasksById.keys {
                if self.tasksById[key]?.status == .done || self.tasksById[key]?.status == .error {
                    self.tasksById[key]?.acknowledged = true
                }
            }
            self.publishSnapshot()
        }
    }

    func resetAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for key in self.tasksById.keys {
                self.tasksById[key]?.acknowledged = true
                if self.tasksById[key]?.status == .working || self.tasksById[key]?.status == .stale {
                    self.tasksById[key]?.status = .done
                }
            }
            self.publishSnapshot()
        }
    }

    func currentSnapshot() -> WatcherSnapshot {
        queue.sync {
            computeSnapshot()
        }
    }

    func recentTasks(limit: Int) -> [TrackedTask] {
        queue.sync {
            orderedIds.prefix(limit).compactMap { tasksById[$0] }
        }
    }

    // MARK: - Watchers & Timers

    private var watchDirectoryURL: URL {
        let expanded = NSString(string: settings.watchFolderPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private var archiveDirectoryURL: URL {
        watchDirectoryURL.appendingPathComponent("archive", isDirectory: true)
    }

    private func ensureDirectoriesExist() {
        try? FileManager.default.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)
    }

    private func attachFileSystemWatcher() {
        folderDescriptor = open(watchDirectoryURL.path, O_EVTONLY)
        guard folderDescriptor >= 0 else { return }

        let fd = folderDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedScan()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fsSource = source
    }

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !FileManager.default.fileExists(atPath: self.watchDirectoryURL.path) {
                self.ensureDirectoriesExist()
                self.fsSource?.cancel()
                self.fsSource = nil
                self.attachFileSystemWatcher()
            }
            self.scanWatchFolder()
        }
        timer.resume()
        pollTimer = timer
    }

    private func startStaleAndCleanupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(15), repeating: .seconds(15), leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.checkStaleWorkingTasks()
            self?.cleanupArchiveOlderThan7DaysIfNeeded(force: false)
        }
        timer.resume()
        staleAndCleanupTimer = timer
    }

    private func scheduleDebouncedScan() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanWatchFolder()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    private func teardownWatchers() {
        debounceWorkItem?.cancel()
        fsSource?.cancel()
        fsSource = nil
        folderDescriptor = -1
        pollTimer?.cancel()
        pollTimer = nil
        staleAndCleanupTimer?.cancel()
        staleAndCleanupTimer = nil
    }

    // MARK: - File Scanning, Stale Detection & 7-Day Archive Retention

    private func scanWatchFolder() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: watchDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let jsonFiles = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !jsonFiles.isEmpty else { return }
        let decoder = JSONDecoder()

        for fileURL in jsonFiles {
            let name = fileURL.lastPathComponent.lowercased()
            guard let data = try? Data(contentsOf: fileURL),
                  let payload = try? decoder.decode(TaskFlagPayload.self, from: data) else {
                continue
            }

            archiveProcessedFile(fileURL)

            let inferredStatus: String
            if let explicit = payload.status, !explicit.isEmpty {
                inferredStatus = explicit
            } else if name.hasPrefix("working-") {
                inferredStatus = "working"
            } else if name.hasPrefix("error-") {
                inferredStatus = "error"
            } else {
                inferredStatus = "done"
            }

            applyEvent(
                rawId: payload.id,
                title: payload.title ?? "Task",
                rawStatus: inferredStatus,
                progress: payload.progress
            )
        }
    }

    private func applyEvent(
        rawId: String?,
        title: String,
        rawStatus: String,
        progress: Double?
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Task" : title
        // Если id не задан, используем детерминированный ключ по названию, чтобы done заменял working той же задачи
        let taskId = (rawId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "title:\(cleanTitle.lowercased())"

        let status: HeadState
        switch rawStatus.lowercased() {
        case "working", "running", "in_progress":
            status = .working
        case "error", "failed", "fail":
            status = .error
        default:
            status = .done
        }

        let clampedProgress = progress.map { min(max($0, 0.0), 1.0) }
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: now)

        let entry = TrackedTask(
            id: taskId,
            title: cleanTitle,
            status: status,
            progress: status == .working ? clampedProgress : nil,
            updatedAt: now,
            formattedTime: timeStr,
            acknowledged: false
        )

        tasksById[taskId] = entry
        orderedIds.removeAll(where: { $0 == taskId })
        orderedIds.insert(taskId, at: 0)
        if orderedIds.count > 30 {
            let overflow = orderedIds.suffix(from: 30)
            for oldId in overflow {
                tasksById.removeValue(forKey: oldId)
            }
            orderedIds = Array(orderedIds.prefix(30))
        }

        if status == .done {
            DispatchQueue.main.async { [weak self] in
                self?.notifier.handleTaskDone(title: cleanTitle)
            }
        } else if status == .error {
            DispatchQueue.main.async { [weak self] in
                self?.notifier.handleTaskError(title: cleanTitle)
            }
        }

        publishSnapshot()
    }

    private func checkStaleWorkingTasks() {
        let timeoutSeconds = max(60.0, settings.staleTimeoutMinutes * 60.0)
        let now = Date()
        var changed = false

        for (id, task) in tasksById where task.status == .working && !task.acknowledged {
            if now.timeIntervalSince(task.updatedAt) >= timeoutSeconds {
                tasksById[id]?.status = .stale
                changed = true
            }
        }

        if changed {
            publishSnapshot()
        }
    }

    private func archiveProcessedFile(_ sourceURL: URL) {
        ensureDirectoriesExist()
        let fm = FileManager.default
        var dest = archiveDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)

        if fm.fileExists(atPath: dest.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let stamp = Int(Date().timeIntervalSince1970)
            dest = archiveDirectoryURL.appendingPathComponent("\(stem)-\(stamp).json")
        }

        do {
            try fm.moveItem(at: sourceURL, to: dest)
        } catch {
            try? fm.removeItem(at: sourceURL)
        }
    }

    private func cleanupArchiveOlderThan7DaysIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastArchiveCleanupDate) >= 3600 else { return }
        lastArchiveCleanupDate = now

        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-7.0 * 24.0 * 3600.0)

        guard let files = try? fm.contentsOfDirectory(
            at: archiveDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in files {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let fileDate = values?.contentModificationDate ?? values?.creationDate ?? now
            if fileDate < cutoff {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Вычисление агрегированного состояния для головы

    private func computeSnapshot() -> WatcherSnapshot {
        let active = orderedIds.compactMap { tasksById[$0] }.filter { !$0.acknowledged }
        guard !active.isEmpty else {
            return WatcherSnapshot(aggregateState: .idle, badgeCount: 0, activeProgress: nil, subtitle: nil)
        }

        let errors = active.filter { $0.status == .error }
        let working = active.filter { $0.status == .working }
        let dones = active.filter { $0.status == .done }
        let stales = active.filter { $0.status == .stale }

        if let firstErr = errors.first {
            return WatcherSnapshot(
                aggregateState: .error,
                badgeCount: active.count,
                activeProgress: nil,
                subtitle: firstErr.title
            )
        }

        if let firstWork = working.first {
            return WatcherSnapshot(
                aggregateState: .working,
                badgeCount: active.count > 1 ? active.count : (dones.count > 0 ? dones.count : 0),
                activeProgress: firstWork.progress,
                subtitle: firstWork.title
            )
        }

        if !dones.isEmpty {
            return WatcherSnapshot(
                aggregateState: .done,
                badgeCount: dones.count,
                activeProgress: nil,
                subtitle: nil
            )
        }

        if let firstStale = stales.first {
            return WatcherSnapshot(
                aggregateState: .stale,
                badgeCount: stales.count,
                activeProgress: firstStale.progress,
                subtitle: firstStale.title
            )
        }

        return WatcherSnapshot(aggregateState: .idle, badgeCount: 0, activeProgress: nil, subtitle: nil)
    }

    private func publishSnapshot() {
        let snap = computeSnapshot()
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotChanged?(snap)
        }
    }
}
