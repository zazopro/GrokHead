import AppKit
import AVFoundation
import Foundation
import UserNotifications

final class SoundAndNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let systemSoundNames = [
        "Glass", "Ping", "Hero", "Purr", "Submarine", "Basso", "Sosumi", "Funk", "Tink"
    ]

    private let settings: AppSettings
    private var audioPlayer: AVAudioPlayer?
    var onNotificationClicked: (() -> Void)?

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        if isBundledApp {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestPermissionsIfNeeded() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Импорт пользовательского звука в ~/Library/Application Support/GrokHead/Sounds/

    static func soundsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("GrokHead/Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func importCustomSoundFile(from sourceURL: URL) -> String? {
        let destDir = Self.soundsDirectoryURL()
        let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        let fm = FileManager.default

        if sourceURL.standardizedFileURL != destURL.standardizedFileURL {
            try? fm.removeItem(at: destURL)
            do {
                try fm.copyItem(at: sourceURL, to: destURL)
            } catch {
                return nil
            }
        }
        return destURL.path
    }

    // MARK: - Проверка «Не беспокоить» (Snooze, Focus, Расписание)

    func isDoNotDisturbActive() -> Bool {
        if settings.isSnoozedNow {
            return true
        }
        if settings.dndRespectFocus && isSystemFocusActive() {
            return true
        }
        if settings.dndScheduleEnabled && isWithinQuietSchedule() {
            return true
        }
        return false
    }

    private func isWithinQuietSchedule() -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = settings.dndStartMinutes
        let end = settings.dndEndMinutes

        if start <= end {
            return nowMinutes >= start && nowMinutes < end
        } else {
            // Ночной интервал через полночь, например 23:00–08:00
            return nowMinutes >= start || nowMinutes < end
        }
    }

    private func isSystemFocusActive() -> Bool {
        let assertionsPath = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: assertionsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let storeData = json["data"] as? [[String: Any]] else {
            return false
        }
        for entry in storeData {
            if let records = entry["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - Озвучивание событий и уведомления macOS

    func handleTaskDone(title: String) {
        if !settings.muteAllSounds && !isDoNotDisturbActive() {
            playSound(namedOrPath: settings.doneSoundIdentifier)
        }

        if settings.notifyOnDone && !settings.isSnoozedNow && isBundledApp {
            let content = UNMutableNotificationContent()
            content.title = L10n.notifDoneTitle
            content.body = title

            let req = UNNotificationRequest(
                identifier: "grokhead.done.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req)
        }
    }

    func handleTaskError(title: String) {
        if !settings.muteAllSounds && !isDoNotDisturbActive() {
            playSound(namedOrPath: settings.errorSoundIdentifier)
        }
    }

    func previewSound(namedOrPath identifier: String) {
        playSound(namedOrPath: identifier)
    }

    private func playSound(namedOrPath identifier: String) {
        let vol = Float(min(max(settings.soundVolume, 0.0), 1.0))
        guard vol > 0.001 else { return }

        // Пользовательский аудиофайл (.mp3, .m4a, .wav, .aiff)
        if identifier.contains("/") && FileManager.default.fileExists(atPath: identifier) {
            let url = URL(fileURLWithPath: identifier)
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = vol
                player.prepareToPlay()
                player.play()
                self.audioPlayer = player
                return
            }
        }

        // Системный звук macOS
        if let sysSound = NSSound(named: NSSound.Name(identifier)) {
            sysSound.stop()
            sysSound.volume = vol
            sysSound.play()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onNotificationClicked?()
        }
        completionHandler()
    }
}
