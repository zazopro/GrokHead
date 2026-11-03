import AppKit
import Foundation
import UniformTypeIdentifiers

@main
enum GrokHeadApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var soundAndNotifier = SoundAndNotifier(settings: settings)
    private lazy var watcher = TaskWatcher(settings: settings, notifier: soundAndNotifier)

    private var panel: FloatingPanel?
    private var headView: HeadView?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var popover: NSPopover?
    private var popoverController: RecentTasksPopoverController?

    private var snoozeTimer: Timer?
    private var isHeadManuallyHidden = false
    private var isHiddenByFullscreenSpace = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMenuShortcuts()

        soundAndNotifier.requestPermissionsIfNeeded()
        soundAndNotifier.onNotificationClicked = { [weak self] in
            self?.handlePrimaryOpenChat()
        }

        setupFloatingPanel()
        setupPopover()
        setupStatusBarItem()
        bindUpdates()
        observeWorkspaceSpaces()

        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    // MARK: - URL Scheme: grokhead://working?id=t1&title=...&progress=0.5

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "grokhead" {
            watcher.handleIncomingURL(url)
        }
    }

    // MARK: - Edit Menu Shortcuts (Cmd+C / Cmd+V / Cmd+A)

    private func setupEditMenuShortcuts() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.settingsMenu, action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.quitMenu, action: #selector(quitAction), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Floating Panel & Dynamic Sizing (48–160 px)

    private func canvasSizeForHead() -> NSSize {
        let d = CGFloat(min(max(settings.headSize, 48), 160))
        let width = max(d + 44, 176)
        let height = d + 54
        return NSSize(width: width, height: height)
    }

    private func setupFloatingPanel() {
        let size = canvasSizeForHead()
        let initialOrigin = settings.savedWindowOrigin() ?? defaultOriginOnSelectedMonitor(canvasSize: size)
        let rect = NSRect(origin: initialOrigin, size: size)

        let floatingPanel = FloatingPanel(contentRect: rect)
        floatingPanel.applyCaptureAndFullscreenPolicy(
            autoHideFullscreenAndCapture: settings.autoHideFullscreenAndCapture
        )

        let view = HeadView(frame: NSRect(origin: .zero, size: size), settings: settings)
        view.updateSnapshot(watcher.currentSnapshot())

        view.onSingleClick = { [weak self] in
            self?.handlePrimaryOpenChat()
        }
        view.onDoubleClick = { [weak self] in
            self?.activateSnoozeForOneHour()
        }
        view.onPositionChanged = { [weak self] newOrigin in
            self?.settings.saveWindowOrigin(newOrigin)
        }
        view.menuProvider = { [weak self] in
            self?.buildHeadRightClickMenu() ?? NSMenu()
        }
        view.onHoverChanged = { [weak self] hovering in
            self?.handleHover(hovering)
        }

        floatingPanel.contentView = view
        floatingPanel.orderFrontRegardless()

        self.headView = view
        self.panel = floatingPanel
    }

    private func resizePanelKeepingHeadCenter() {
        guard let panel, let headView else { return }
        let oldFrame = panel.frame
        let newSize = canvasSizeForHead()
        let newOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2.0,
            y: oldFrame.midY - newSize.height / 2.0
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)
        panel.setFrame(newFrame, display: true)
        headView.frame = NSRect(origin: .zero, size: newSize)
        headView.reloadAppearance()
    }

    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        let idx = settings.selectedMonitorIndex
        if idx >= 0 && idx < screens.count {
            return screens[idx]
        }
        return NSScreen.main ?? screens.first!
    }

    private func defaultOriginOnSelectedMonitor(canvasSize: NSSize) -> NSPoint {
        guard !NSScreen.screens.isEmpty else {
            return NSPoint(x: 1180, y: 80)
        }
        let visibleFrame = targetScreen().visibleFrame
        return NSPoint(
            x: visibleFrame.maxX - canvasSize.width - 24,
            y: visibleFrame.minY + 32
        )
    }

    func movePanelToSelectedMonitor() {
        guard let panel else { return }
        let origin = defaultOriginOnSelectedMonitor(canvasSize: panel.frame.size)
        panel.setFrameOrigin(origin)
        settings.saveWindowOrigin(origin)
    }

    // MARK: - Fullscreen Space Observer

    private func observeWorkspaceSpaces() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateFullscreenVisibility()
        }
    }

    private func evaluateFullscreenVisibility() {
        guard let panel else { return }
        panel.applyCaptureAndFullscreenPolicy(
            autoHideFullscreenAndCapture: settings.autoHideFullscreenAndCapture
        )

        if !settings.autoHideFullscreenAndCapture {
            isHiddenByFullscreenSpace = false
            updatePanelVisibility()
            return
        }

        // При включённой опции автоскрытия проверяем, перекрыт ли экран полноэкранным окном (menubar hidden)
        let menuBarVisible = NSMenu.menuBarVisible()
        isHiddenByFullscreenSpace = !menuBarVisible
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if isHeadManuallyHidden || isHiddenByFullscreenSpace {
            popover?.performClose(nil)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Hover Popover

    private func setupPopover() {
        let controller = RecentTasksPopoverController()
        controller.update(tasks: watcher.recentTasks(limit: 5))

        let pop = NSPopover()
        pop.behavior = .semitransient
        pop.animates = true
        pop.contentViewController = controller

        self.popoverController = controller
        self.popover = pop
    }

    private func handleHover(_ hovering: Bool) {
        guard let contentView = panel?.contentView, let popover else { return }
        if hovering {
            popoverController?.update(tasks: watcher.recentTasks(limit: 5))
            if !popover.isShown {
                popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minX)
            }
        } else {
            popover.performClose(nil)
        }
    }

    // MARK: - Menu Bar (NSStatusItem) & Right-Click Task List

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarButton(for: item)
        item.menu = buildStatusBarMenu()
        self.statusItem = item
    }

    private func updateStatusBarButton(for item: NSStatusItem? = nil) {
        guard let button = (item ?? statusItem)?.button else { return }
        let snap = watcher.currentSnapshot()
        let symbol: String
        switch snap.aggregateState {
        case .error: symbol = "exclamationmark.bubble.fill"
        case .done: symbol = "checkmark.bubble.fill"
        case .working, .stale: symbol = "ellipsis.bubble.fill"
        case .idle: symbol = "bubble.left.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GrokHead")
        button.image?.isTemplate = true
        button.title = snap.badgeCount > 0 ? " \(snap.badgeCount)" : ""
    }

    private func bindUpdates() {
        watcher.onSnapshotChanged = { [weak self] snapshot in
            guard let self else { return }
            self.headView?.updateSnapshot(snapshot)
            self.popoverController?.update(tasks: self.watcher.recentTasks(limit: 5))
            self.updateStatusBarButton()
            self.statusItem?.menu = self.buildStatusBarMenu()
        }

        NotificationCenter.default.addObserver(
            forName: .grokHeadSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.resizePanelKeepingHeadCenter()
            self.evaluateFullscreenVisibility()
            self.statusItem?.menu = self.buildStatusBarMenu()
            self.setupEditMenuShortcuts()
        }

        NotificationCenter.default.addObserver(
            forName: .grokHeadMonitorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.movePanelToSelectedMonitor()
        }
    }

    private func buildHeadRightClickMenu() -> NSMenu {
        let menu = NSMenu()

        // Список активных / последних задач прямо по правому клику
        let tasks = watcher.recentTasks(limit: 10)
        let headerItem = NSMenuItem(title: L10n.activeTasksHeader, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if tasks.isEmpty {
            let empty = NSMenuItem(title: "  \(L10n.noTasksYet)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for t in tasks {
                let prefix = statusPrefix(for: t.status)
                let pct = t.progress.map { " (\(Int(($0 * 100).rounded()))%)" } ?? ""
                let line = "\(prefix) \(t.title)\(pct)  [\(t.formattedTime)]"
                let taskItem = NSMenuItem(title: line, action: #selector(openChatAction), keyEquivalent: "")
                taskItem.target = self
                menu.addItem(taskItem)
            }
        }

        menu.addItem(.separator())
        appendCommonMenuActions(to: menu)
        return menu
    }

    private func buildStatusBarMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleTitle = isHeadManuallyHidden ? L10n.showHead : L10n.hideHead
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleHeadVisibilityAction), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        // Подменю последних 10 задач
        let recentSubmenuItem = NSMenuItem(title: L10n.recentTasksMenu, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let recent = watcher.recentTasks(limit: 10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: L10n.noTasksYet, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for t in recent {
                let prefix = statusPrefix(for: t.status)
                let item = NSMenuItem(
                    title: "\(prefix) \(t.title) — \(t.formattedTime)",
                    action: #selector(openChatAction),
                    keyEquivalent: ""
                )
                item.target = self
                submenu.addItem(item)
            }
        }
        recentSubmenuItem.submenu = submenu
        menu.addItem(recentSubmenuItem)

        menu.addItem(.separator())
        appendCommonMenuActions(to: menu)
        return menu
    }

    private func appendCommonMenuActions(to menu: NSMenu) {
        let openItem = NSMenuItem(title: L10n.openChat, action: #selector(openChatAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let resetItem = NSMenuItem(title: L10n.resetTasks, action: #selector(resetStateAction), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        let snoozeTitle = settings.isSnoozedNow ? L10n.unsnoozeNow : L10n.snoozeOneHour
        let snoozeItem = NSMenuItem(title: snoozeTitle, action: #selector(toggleSnoozeAction), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.settingsMenu, action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitMenu, action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func statusPrefix(for state: HeadState) -> String {
        switch state {
        case .working: return "⏳"
        case .stale:   return "⏸"
        case .done:    return "✓"
        case .error:   return "⚠️"
        case .idle:    return "•"
        }
    }

    // MARK: - Actions

    @objc private func toggleHeadVisibilityAction() {
        isHeadManuallyHidden.toggle()
        updatePanelVisibility()
        statusItem?.menu = buildStatusBarMenu()
    }

    @objc private func openChatAction() {
        handlePrimaryOpenChat()
    }

    func handlePrimaryOpenChat() {
        popover?.performClose(nil)
        watcher.acknowledgeCompletedAndErrors()
        openConfiguredDestination()
    }

    private func openConfiguredDestination() {
        let trimmed = settings.openURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        let fallback = settings.fallbackApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return }

        if let appURL = resolveApplicationURL(for: fallback) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }
    }

    private func resolveApplicationURL(for identifierOrName: String) -> URL? {
        if let byBundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifierOrName) {
            return byBundle
        }
        let cleanName = identifierOrName.hasSuffix(".app")
            ? String(identifierOrName.dropLast(4))
            : identifierOrName

        for root in ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"] {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent("\(cleanName).app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @objc private func resetStateAction() {
        popover?.performClose(nil)
        watcher.resetAll()
    }

    @objc private func toggleSnoozeAction() {
        if settings.isSnoozedNow {
            settings.snoozeUntil = nil
            snoozeTimer?.invalidate()
            snoozeTimer = nil
        } else {
            activateSnoozeForOneHour()
        }
        statusItem?.menu = buildStatusBarMenu()
    }

    func activateSnoozeForOneHour() {
        snoozeTimer?.invalidate()
        settings.snoozeUntil = Date().addingTimeInterval(3600)
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            self?.settings.snoozeUntil = nil
            self?.statusItem?.menu = self?.buildStatusBarMenu()
        }
        statusItem?.menu = buildStatusBarMenu()
    }

    @objc private func openSettingsAction() {
        activateApplication()

        if settingsWindow == nil {
            let controller = SettingsViewController(
                settings: settings,
                soundAndNotifier: soundAndNotifier,
                onWatchFolderChanged: { [weak self] in self?.watcher.restart() }
            )
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.settingsWindowTitle
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 540, height: 520))
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }

        settingsWindow?.title = L10n.settingsWindowTitle
        if let vc = settingsWindow?.contentViewController as? SettingsViewController {
            vc.refreshFromSettings()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
