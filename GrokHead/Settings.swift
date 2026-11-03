import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

extension Notification.Name {
    static let grokHeadSettingsDidChange = Notification.Name("com.grokhead.settingsDidChange")
    static let grokHeadMonitorDidChange = Notification.Name("com.grokhead.monitorDidChange")
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let language = "grokhead.language"
        static let watchFolderPath = "grokhead.watchFolderPath"
        static let openURL = "grokhead.openURL"
        static let fallbackApp = "grokhead.fallbackApp"
        static let customAvatarPath = "grokhead.customAvatarPath"
        static let headSize = "grokhead.headSize"
        static let staleTimeoutMinutes = "grokhead.staleTimeoutMinutes"
        static let doneSoundIdentifier = "grokhead.doneSoundIdentifier"
        static let errorSoundIdentifier = "grokhead.errorSoundIdentifier"
        static let muteAllSounds = "grokhead.muteAllSounds"
        static let soundVolume = "grokhead.soundVolume"
        static let dndRespectFocus = "grokhead.dndRespectFocus"
        static let dndScheduleEnabled = "grokhead.dndScheduleEnabled"
        static let dndStartMinutes = "grokhead.dndStartMinutes"
        static let dndEndMinutes = "grokhead.dndEndMinutes"
        static let notifyOnDone = "grokhead.notifyOnDone"
        static let selectedMonitorIndex = "grokhead.selectedMonitorIndex"
        static let autoHideFullscreenAndCapture = "grokhead.autoHideFullscreenAndCapture"
        static let windowX = "grokhead.windowX"
        static let windowY = "grokhead.windowY"
        static let hasSavedPosition = "grokhead.hasSavedPosition"
        static let snoozeUntilEpoch = "grokhead.snoozeUntilEpoch"
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            notifyChanged()
        }
    }

    var watchFolderPath: String {
        didSet {
            defaults.set(watchFolderPath, forKey: Keys.watchFolderPath)
            notifyChanged()
        }
    }

    var openURL: String {
        didSet { defaults.set(openURL, forKey: Keys.openURL) }
    }

    var fallbackApp: String {
        didSet { defaults.set(fallbackApp, forKey: Keys.fallbackApp) }
    }

    var customAvatarPath: String {
        didSet {
            defaults.set(customAvatarPath, forKey: Keys.customAvatarPath)
            notifyChanged()
        }
    }

    var headSize: Double {
        didSet {
            defaults.set(headSize, forKey: Keys.headSize)
            notifyChanged()
        }
    }

    var staleTimeoutMinutes: Double {
        didSet { defaults.set(staleTimeoutMinutes, forKey: Keys.staleTimeoutMinutes) }
    }

    var doneSoundIdentifier: String {
        didSet { defaults.set(doneSoundIdentifier, forKey: Keys.doneSoundIdentifier) }
    }

    var errorSoundIdentifier: String {
        didSet { defaults.set(errorSoundIdentifier, forKey: Keys.errorSoundIdentifier) }
    }

    var muteAllSounds: Bool {
        didSet {
            defaults.set(muteAllSounds, forKey: Keys.muteAllSounds)
            notifyChanged()
        }
    }

    var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) }
    }

    var dndRespectFocus: Bool {
        didSet { defaults.set(dndRespectFocus, forKey: Keys.dndRespectFocus) }
    }

    var dndScheduleEnabled: Bool {
        didSet { defaults.set(dndScheduleEnabled, forKey: Keys.dndScheduleEnabled) }
    }

    var dndStartMinutes: Int {
        didSet { defaults.set(dndStartMinutes, forKey: Keys.dndStartMinutes) }
    }

    var dndEndMinutes: Int {
        didSet { defaults.set(dndEndMinutes, forKey: Keys.dndEndMinutes) }
    }

    var notifyOnDone: Bool {
        didSet { defaults.set(notifyOnDone, forKey: Keys.notifyOnDone) }
    }

    var selectedMonitorIndex: Int {
        didSet {
            defaults.set(selectedMonitorIndex, forKey: Keys.selectedMonitorIndex)
            NotificationCenter.default.post(name: .grokHeadMonitorDidChange, object: self)
        }
    }

    var autoHideFullscreenAndCapture: Bool {
        didSet {
            defaults.set(autoHideFullscreenAndCapture, forKey: Keys.autoHideFullscreenAndCapture)
            notifyChanged()
        }
    }

    var launchAtLogin: Bool {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                Task { try? await SMAppService.mainApp.unregister() }
            }
        }
    }

    var snoozeUntil: Date? {
        get {
            let epoch = defaults.double(forKey: Keys.snoozeUntilEpoch)
            guard epoch > 0 else { return nil }
            let date = Date(timeIntervalSince1970: epoch)
            return date > Date() ? date : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.snoozeUntilEpoch)
        }
    }

    var isSnoozedNow: Bool {
        snoozeUntil != nil
    }

    private init() {
        let sysRu = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? true
        let defaultLang = AppLanguage(rawValue: "ru") ?? (sysRu ? .ru : .en)
        self.language = (defaults.string(forKey: Keys.language)).flatMap(AppLanguage.init(rawValue:)) ?? defaultLang

        self.watchFolderPath = defaults.string(forKey: Keys.watchFolderPath) ?? "~/Downloads/grokhead"
        self.openURL = defaults.string(forKey: Keys.openURL) ?? "grokbot://app/v1/"
        self.fallbackApp = defaults.string(forKey: Keys.fallbackApp) ?? "Telegram"
        self.customAvatarPath = defaults.string(forKey: Keys.customAvatarPath) ?? ""

        let storedSize = defaults.double(forKey: Keys.headSize)
        self.headSize = (storedSize >= 48 && storedSize <= 160) ? storedSize : 76.0

        let storedStale = defaults.double(forKey: Keys.staleTimeoutMinutes)
        self.staleTimeoutMinutes = storedStale >= 1 ? storedStale : 30.0

        self.doneSoundIdentifier = defaults.string(forKey: Keys.doneSoundIdentifier) ?? "Glass"
        self.errorSoundIdentifier = defaults.string(forKey: Keys.errorSoundIdentifier) ?? "Basso"
        self.muteAllSounds = defaults.bool(forKey: Keys.muteAllSounds)

        if defaults.object(forKey: Keys.soundVolume) != nil {
            self.soundVolume = defaults.double(forKey: Keys.soundVolume)
        } else {
            self.soundVolume = 0.8
        }

        if defaults.object(forKey: Keys.dndRespectFocus) != nil {
            self.dndRespectFocus = defaults.bool(forKey: Keys.dndRespectFocus)
        } else {
            self.dndRespectFocus = true
        }

        self.dndScheduleEnabled = defaults.bool(forKey: Keys.dndScheduleEnabled)
        self.dndStartMinutes = defaults.object(forKey: Keys.dndStartMinutes) != nil
            ? defaults.integer(forKey: Keys.dndStartMinutes) : (23 * 60)
        self.dndEndMinutes = defaults.object(forKey: Keys.dndEndMinutes) != nil
            ? defaults.integer(forKey: Keys.dndEndMinutes) : (8 * 60)

        if defaults.object(forKey: Keys.notifyOnDone) != nil {
            self.notifyOnDone = defaults.bool(forKey: Keys.notifyOnDone)
        } else {
            self.notifyOnDone = true
        }

        self.selectedMonitorIndex = defaults.integer(forKey: Keys.selectedMonitorIndex)
        self.autoHideFullscreenAndCapture = defaults.bool(forKey: Keys.autoHideFullscreenAndCapture)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func savedWindowOrigin() -> NSPoint? {
        guard defaults.bool(forKey: Keys.hasSavedPosition) else { return nil }
        return NSPoint(
            x: defaults.double(forKey: Keys.windowX),
            y: defaults.double(forKey: Keys.windowY)
        )
    }

    func saveWindowOrigin(_ point: NSPoint) {
        defaults.set(point.x, forKey: Keys.windowX)
        defaults.set(point.y, forKey: Keys.windowY)
        defaults.set(true, forKey: Keys.hasSavedPosition)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .grokHeadSettingsDidChange, object: self)
    }
}

// MARK: - Вкладочное окно настроек на чистом AppKit (RU / EN, без SwiftUI)

final class SettingsViewController: NSViewController, NSTextFieldDelegate {
    private let settings: AppSettings
    private let soundAndNotifier: SoundAndNotifier
    private let onWatchFolderChanged: () -> Void

    private let tabView = NSTabView()

    // Tab 1: General
    private let languagePopup = NSPopUpButton()
    private let folderField = NSTextField()
    private let openURLField = NSTextField()
    private let fallbackAppField = NSTextField()
    private let staleField = NSTextField()
    private let avatarStatusLabel = NSTextField(labelWithString: "")
    private let resetAvatarButton = NSButton()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider()

    // Tab 2: Sound & DND
    private let doneSoundPopup = NSPopUpButton()
    private let errorSoundPopup = NSPopUpButton()
    private let muteCheckbox = NSButton()
    private let volumeLabel = NSTextField(labelWithString: "")
    private let volumeSlider = NSSlider()
    private let dndFocusCheckbox = NSButton()
    private let dndScheduleCheckbox = NSButton()
    private let dndStartField = NSTextField()
    private let dndEndField = NSTextField()

    // Tab 3: Display & System
    private let monitorPopup = NSPopUpButton()
    private let notifyDoneCheckbox = NSButton()
    private let autoHideCheckbox = NSButton()
    private let launchAtLoginCheckbox = NSButton()

    init(
        settings: AppSettings,
        soundAndNotifier: SoundAndNotifier,
        onWatchFolderChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.soundAndNotifier = soundAndNotifier
        self.onWatchFolderChanged = onWatchFolderChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 520))
        tabView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            tabView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        buildTabs()
        self.view = root
        refreshFromSettings()
    }

    private func buildTabs() {
        for item in tabView.tabViewItems {
            tabView.removeTabViewItem(item)
        }

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = L10n.tabGeneral
        generalItem.view = buildGeneralTabView()
        tabView.addTabViewItem(generalItem)

        let soundItem = NSTabViewItem(identifier: "sound")
        soundItem.label = L10n.tabSound
        soundItem.view = buildSoundTabView()
        tabView.addTabViewItem(soundItem)

        let displayItem = NSTabViewItem(identifier: "display")
        displayItem.label = L10n.tabDisplay
        displayItem.view = buildDisplayTabView()
        tabView.addTabViewItem(displayItem)
    }

    private func buildGeneralTabView() -> NSView {
        let container = NSView()
        let stack = makeRootStack(in: container)

        // Язык RU / EN
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: ["Русский", "English"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        addRow(label: L10n.tr("Язык интерфейса:", "Language:"), control: languagePopup, to: stack)

        // Папка слежения
        folderField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        folderField.delegate = self
        let browseBtn = NSButton(title: L10n.tr("Обзор…", "Browse…"), target: self, action: #selector(pickFolderClicked))
        browseBtn.bezelStyle = .rounded
        let folderRow = NSStackView(views: [folderField, browseBtn])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8
        folderField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addRow(label: L10n.tr("Папка флагов:", "Watch Folder:"), control: folderRow, to: stack)

        // Ссылка по клику (по умолчанию grokbot://app/v1/)
        openURLField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        openURLField.placeholderString = "grokbot://app/v1/"
        openURLField.delegate = self
        addRow(label: L10n.tr("Ссылка по клику:", "Click URL:"), control: openURLField, to: stack)

        fallbackAppField.font = NSFont.systemFont(ofSize: 12)
        fallbackAppField.delegate = self
        addRow(label: L10n.tr("Запасное приложение:", "Fallback App:"), control: fallbackAppField, to: stack)

        staleField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        staleField.delegate = self
        staleField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        addRow(label: L10n.tr("Таймаут зависания (мин):", "Stale Timeout (min):"), control: staleField, to: stack)

        // Внешний вид головы и слайдер 48–160 px
        let pickImgBtn = NSButton(title: L10n.tr("Свой PNG/JPG…", "Custom PNG/JPG…"), target: self, action: #selector(pickAvatarClicked))
        pickImgBtn.bezelStyle = .rounded
        resetAvatarButton.title = L10n.tr("Глаза Grok Bot", "Grok Bot Eyes")
        resetAvatarButton.bezelStyle = .rounded
        resetAvatarButton.target = self
        resetAvatarButton.action = #selector(resetAvatarClicked)
        avatarStatusLabel.font = NSFont.systemFont(ofSize: 11)
        avatarStatusLabel.textColor = .secondaryLabelColor
        avatarStatusLabel.lineBreakMode = .byTruncatingMiddle

        let avatarRow = NSStackView(views: [avatarStatusLabel, pickImgBtn, resetAvatarButton])
        avatarRow.orientation = .horizontal
        avatarRow.spacing = 8
        addRow(label: L10n.tr("Вид головы:", "Appearance:"), control: avatarRow, to: stack)

        sizeSlider.minValue = 48
        sizeSlider.maxValue = 160
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeSliderChanged)
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let sizeRow = NSStackView(views: [sizeSlider, sizeLabel])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 10
        sizeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addRow(label: L10n.tr("Размер (48–160 px):", "Head Size (48–160 px):"), control: sizeRow, to: stack)

        return container
    }

    private func buildSoundTabView() -> NSView {
        let container = NSView()
        let stack = makeRootStack(in: container)

        // Звук Done
        doneSoundPopup.target = self
        doneSoundPopup.action = #selector(doneSoundChanged)
        let chooseDoneBtn = NSButton(title: L10n.tr("Файл…", "File…"), target: self, action: #selector(chooseCustomDoneSound))
        chooseDoneBtn.bezelStyle = .rounded
        let previewDoneBtn = NSButton(title: L10n.tr("Прослушать", "Preview"), target: self, action: #selector(previewDoneClicked))
        previewDoneBtn.bezelStyle = .rounded
        let doneRow = NSStackView(views: [doneSoundPopup, chooseDoneBtn, previewDoneBtn])
        doneRow.orientation = .horizontal
        doneRow.spacing = 6
        addRow(label: L10n.tr("Звук «Готово»:", "Done Sound:"), control: doneRow, to: stack)

        // Звук Error
        errorSoundPopup.target = self
        errorSoundPopup.action = #selector(errorSoundChanged)
        let chooseErrBtn = NSButton(title: L10n.tr("Файл…", "File…"), target: self, action: #selector(chooseCustomErrorSound))
        chooseErrBtn.bezelStyle = .rounded
        let previewErrBtn = NSButton(title: L10n.tr("Прослушать", "Preview"), target: self, action: #selector(previewErrorClicked))
        previewErrBtn.bezelStyle = .rounded
        let errRow = NSStackView(views: [errorSoundPopup, chooseErrBtn, previewErrBtn])
        errRow.orientation = .horizontal
        errRow.spacing = 6
        addRow(label: L10n.tr("Звук «Ошибка»:", "Error Sound:"), control: errRow, to: stack)

        // Громкость + Без звука
        volumeSlider.minValue = 0.0
        volumeSlider.maxValue = 1.0
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        volumeLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let volRow = NSStackView(views: [volumeSlider, volumeLabel])
        volRow.orientation = .horizontal
        volRow.spacing = 10
        addRow(label: L10n.tr("Громкость:", "Volume:"), control: volRow, to: stack)

        muteCheckbox.setButtonType(.switch)
        muteCheckbox.title = L10n.tr("Без звука", "Mute All Sounds")
        muteCheckbox.target = self
        muteCheckbox.action = #selector(muteChanged)
        stack.addArrangedSubview(muteCheckbox)

        let sep = NSBox()
        sep.boxType = .separator
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Не беспокоить (Focus + расписание 23:00–08:00)
        dndFocusCheckbox.setButtonType(.switch)
        dndFocusCheckbox.title = L10n.tr(
            "Не беспокоить при включённом режиме «Фокусирование» macOS",
            "Mute when macOS Focus mode is active"
        )
        dndFocusCheckbox.target = self
        dndFocusCheckbox.action = #selector(dndFocusChanged)
        stack.addArrangedSubview(dndFocusCheckbox)

        dndScheduleCheckbox.setButtonType(.switch)
        dndScheduleCheckbox.title = L10n.tr("Тихие часы по расписанию:", "Scheduled Quiet Hours:")
        dndScheduleCheckbox.target = self
        dndScheduleCheckbox.action = #selector(dndScheduleChanged)
        stack.addArrangedSubview(dndScheduleCheckbox)

        dndStartField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dndStartField.delegate = self
        dndStartField.widthAnchor.constraint(equalToConstant: 68).isActive = true

        dndEndField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dndEndField.delegate = self
        dndEndField.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let dash = NSTextField(labelWithString: "—")
        let schedRow = NSStackView(views: [dndStartField, dash, dndEndField])
        schedRow.orientation = .horizontal
        schedRow.spacing = 8
        addRow(label: L10n.tr("Интервал (ЧЧ:ММ):", "Interval (HH:MM):"), control: schedRow, to: stack)

        return container
    }

    private func buildDisplayTabView() -> NSView {
        let container = NSView()
        let stack = makeRootStack(in: container)

        monitorPopup.target = self
        monitorPopup.action = #selector(monitorChanged)
        addRow(label: L10n.tr("Монитор:", "Monitor:"), control: monitorPopup, to: stack)

        notifyDoneCheckbox.setButtonType(.switch)
        notifyDoneCheckbox.title = L10n.tr(
            "Показывать системное уведомление macOS при завершении задачи (клик открывает чат)",
            "Show macOS notification on Done (click opens chat)"
        )
        notifyDoneCheckbox.target = self
        notifyDoneCheckbox.action = #selector(notifyDoneChanged)
        stack.addArrangedSubview(notifyDoneCheckbox)

        autoHideCheckbox.setButtonType(.switch)
        autoHideCheckbox.title = L10n.tr(
            "Скрывать в полноэкранных приложениях и при демонстрации/записи экрана",
            "Auto-hide in fullscreen apps and during screen sharing/recording"
        )
        autoHideCheckbox.target = self
        autoHideCheckbox.action = #selector(autoHideChanged)
        stack.addArrangedSubview(autoHideCheckbox)

        launchAtLoginCheckbox.setButtonType(.switch)
        launchAtLoginCheckbox.title = L10n.tr(
            "Запускать автоматически при входе в систему (SMAppService)",
            "Launch at Login (SMAppService)"
        )
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        stack.addArrangedSubview(launchAtLoginCheckbox)

        let hint = NSTextField(wrappingLabelWithString: L10n.tr(
            "Совет: двойной клик по голове откладывает звуки и уведомления на 1 час.",
            "Tip: Double-clicking the head snoozes sounds and notifications for 1 hour."
        ))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        return container
    }

    private func makeRootStack(in container: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18)
        ])
        return stack
    }

    private func addRow(label: String, control: NSView, to stack: NSStackView) {
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.widthAnchor.constraint(equalToConstant: 165).isActive = true

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.spacing = 10
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func refreshFromSettings() {
        guard isViewLoaded else { return }

        languagePopup.selectItem(at: settings.language == .ru ? 0 : 1)
        folderField.stringValue = settings.watchFolderPath
        openURLField.stringValue = settings.openURL
        fallbackAppField.stringValue = settings.fallbackApp
        staleField.stringValue = "\(Int(settings.staleTimeoutMinutes.rounded()))"

        if settings.customAvatarPath.isEmpty {
            avatarStatusLabel.stringValue = L10n.tr("Встроенные глаза Grok Bot", "Built-in Grok Bot Eyes")
            resetAvatarButton.isHidden = true
        } else {
            avatarStatusLabel.stringValue = URL(fileURLWithPath: settings.customAvatarPath).lastPathComponent
            resetAvatarButton.isHidden = false
        }

        sizeSlider.doubleValue = settings.headSize
        sizeLabel.stringValue = "\(Int(settings.headSize.rounded())) px"

        populateSoundPopup(doneSoundPopup, selected: settings.doneSoundIdentifier)
        populateSoundPopup(errorSoundPopup, selected: settings.errorSoundIdentifier)

        muteCheckbox.state = settings.muteAllSounds ? .on : .off
        volumeSlider.doubleValue = settings.soundVolume
        volumeLabel.stringValue = "\(Int((settings.soundVolume * 100).rounded()))%"

        dndFocusCheckbox.state = settings.dndRespectFocus ? .on : .off
        dndScheduleCheckbox.state = settings.dndScheduleEnabled ? .on : .off
        dndStartField.stringValue = formatMinutes(settings.dndStartMinutes)
        dndEndField.stringValue = formatMinutes(settings.dndEndMinutes)

        monitorPopup.removeAllItems()
        let screens = NSScreen.screens
        for (idx, screen) in screens.enumerated() {
            monitorPopup.addItem(withTitle: "\(idx + 1): \(screen.localizedName)")
        }
        if settings.selectedMonitorIndex < screens.count {
            monitorPopup.selectItem(at: max(0, settings.selectedMonitorIndex))
        }

        notifyDoneCheckbox.state = settings.notifyOnDone ? .on : .off
        autoHideCheckbox.state = settings.autoHideFullscreenAndCapture ? .on : .off
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
    }

    private func populateSoundPopup(_ popup: NSPopUpButton, selected: String) {
        popup.removeAllItems()
        popup.addItems(withTitles: SoundAndNotifier.systemSoundNames)
        if selected.contains("/") {
            let customTitle = URL(fileURLWithPath: selected).lastPathComponent
            popup.addItem(withTitle: customTitle)
            popup.selectItem(withTitle: customTitle)
        } else if SoundAndNotifier.systemSoundNames.contains(selected) {
            popup.selectItem(withTitle: selected)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func formatMinutes(_ total: Int) -> String {
        let h = (total / 60) % 24
        let m = total % 60
        return String(format: "%02d:%02d", h, m)
    }

    private func parseMinutes(_ raw: String) -> Int? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    // MARK: - Actions & NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === openURLField {
            settings.openURL = field.stringValue
        } else if field === fallbackAppField {
            settings.fallbackApp = field.stringValue
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === folderField {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != settings.watchFolderPath {
                settings.watchFolderPath = trimmed
                onWatchFolderChanged()
            }
        } else if field === staleField, let val = Double(field.stringValue), val >= 1 {
            settings.staleTimeoutMinutes = val
        } else if field === dndStartField, let mins = parseMinutes(field.stringValue) {
            settings.dndStartMinutes = mins
        } else if field === dndEndField, let mins = parseMinutes(field.stringValue) {
            settings.dndEndMinutes = mins
        }
    }

    @objc private func languageChanged() {
        let selectedIndex = tabView.indexOfTabViewItem(tabView.selectedTabViewItem!)
        settings.language = (languagePopup.indexOfSelectedItem == 0) ? .ru : .en
        view.window?.title = L10n.settingsWindowTitle
        buildTabs()
        tabView.selectTabViewItem(at: selectedIndex)
        refreshFromSettings()
    }

    @objc private func pickFolderClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.watchFolderPath = url.path
            onWatchFolderChanged()
            refreshFromSettings()
        }
    }

    @objc private func pickAvatarClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            settings.customAvatarPath = url.path
            refreshFromSettings()
        }
    }

    @objc private func resetAvatarClicked() {
        settings.customAvatarPath = ""
        refreshFromSettings()
    }

    @objc private func sizeSliderChanged() {
        let snapped = (sizeSlider.doubleValue / 2.0).rounded() * 2.0
        settings.headSize = min(160, max(48, snapped))
        sizeLabel.stringValue = "\(Int(settings.headSize)) px"
    }

    @objc private func doneSoundChanged() {
        guard let title = doneSoundPopup.titleOfSelectedItem else { return }
        if SoundAndNotifier.systemSoundNames.contains(title) {
            settings.doneSoundIdentifier = title
        }
    }

    @objc private func errorSoundChanged() {
        guard let title = errorSoundPopup.titleOfSelectedItem else { return }
        if SoundAndNotifier.systemSoundNames.contains(title) {
            settings.errorSoundIdentifier = title
        }
    }

    @objc private func chooseCustomDoneSound() {
        if let copiedPath = pickAndImportAudioFile() {
            settings.doneSoundIdentifier = copiedPath
            refreshFromSettings()
        }
    }

    @objc private func chooseCustomErrorSound() {
        if let copiedPath = pickAndImportAudioFile() {
            settings.errorSoundIdentifier = copiedPath
            refreshFromSettings()
        }
    }

    private func pickAndImportAudioFile() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return soundAndNotifier.importCustomSoundFile(from: url)
    }

    @objc private func previewDoneClicked() {
        soundAndNotifier.previewSound(namedOrPath: settings.doneSoundIdentifier)
    }

    @objc private func previewErrorClicked() {
        soundAndNotifier.previewSound(namedOrPath: settings.errorSoundIdentifier)
    }

    @objc private func volumeChanged() {
        settings.soundVolume = volumeSlider.doubleValue
        volumeLabel.stringValue = "\(Int((settings.soundVolume * 100).rounded()))%"
    }

    @objc private func muteChanged() {
        settings.muteAllSounds = (muteCheckbox.state == .on)
    }

    @objc private func dndFocusChanged() {
        settings.dndRespectFocus = (dndFocusCheckbox.state == .on)
    }

    @objc private func dndScheduleChanged() {
        settings.dndScheduleEnabled = (dndScheduleCheckbox.state == .on)
    }

    @objc private func monitorChanged() {
        settings.selectedMonitorIndex = max(0, monitorPopup.indexOfSelectedItem)
    }

    @objc private func notifyDoneChanged() {
        settings.notifyOnDone = (notifyDoneCheckbox.state == .on)
    }

    @objc private func autoHideChanged() {
        settings.autoHideFullscreenAndCapture = (autoHideCheckbox.state == .on)
    }

    @objc private func launchAtLoginChanged() {
        settings.launchAtLogin = (launchAtLoginCheckbox.state == .on)
    }
}
