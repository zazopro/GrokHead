import AppKit
import Darwin
import QuartzCore

final class HeadView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onPositionChanged: ((NSPoint) -> Void)?
    var menuProvider: (() -> NSMenu)?
    var onHoverChanged: ((Bool) -> Void)?

    private let settings: AppSettings
    private var snapshot = WatcherSnapshot(
        aggregateState: .idle,
        badgeCount: 0,
        activeProgress: nil,
        subtitle: nil
    )

    // Слои Core Animation: кольца, тёмная сфера Grok Bot, светящиеся глаза, подпись и бейдж
    private let trackRingLayer = CAShapeLayer()
    private let activeRingLayer = CAShapeLayer()
    private let bodyContainerLayer = CALayer()
    private let sphereLayer = CALayer()
    private let customImageLayer = CALayer()
    private let eyesContainerLayer = CALayer()
    private let leftEyeLayer = CAShapeLayer()
    private let rightEyeLayer = CAShapeLayer()
    private let badgeBackgroundLayer = CALayer()
    private let badgeTextLayer = CATextLayer()
    private let subtitleBgLayer = CALayer()
    private let subtitleTextLayer = CATextLayer()

    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var didDragWindow = false
    private var trackingAreaRef: NSTrackingArea?
    private var pendingSingleClickWork: DispatchWorkItem?

    init(frame frameRect: NSRect, settings: AppSettings) {
        self.settings = settings
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
        reloadAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        customImageLayer.contentsScale = scale
        badgeTextLayer.contentsScale = scale
        subtitleTextLayer.contentsScale = scale
    }

    func updateSnapshot(_ next: WatcherSnapshot) {
        let stateChanged = (next.aggregateState != snapshot.aggregateState)
        snapshot = next
        layoutHeadLayers()
        if stateChanged {
            applyAnimationsAndEyeExpression()
        } else {
            updateRingProgressAndColors()
        }
    }

    func reloadAppearance() {
        reloadCustomAvatarIfNeeded()
        layoutHeadLayers()
        applyAnimationsAndEyeExpression()
    }

    // MARK: - Настройка слоёв Core Animation

    private func setupLayers() {
        guard let root = self.layer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        trackRingLayer.fillColor = nil
        trackRingLayer.lineWidth = 3.0
        trackRingLayer.isHidden = true
        root.addSublayer(trackRingLayer)

        activeRingLayer.fillColor = nil
        activeRingLayer.lineWidth = 3.0
        activeRingLayer.lineCap = .round
        activeRingLayer.isHidden = true
        root.addSublayer(activeRingLayer)

        bodyContainerLayer.shadowColor = NSColor.black.cgColor
        bodyContainerLayer.shadowOpacity = 0.34
        bodyContainerLayer.shadowRadius = 7.0
        bodyContainerLayer.shadowOffset = CGSize(width: 0, height: -3)
        root.addSublayer(bodyContainerLayer)

        sphereLayer.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.15, alpha: 1.0).cgColor
        sphereLayer.borderWidth = 1.2
        sphereLayer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        sphereLayer.masksToBounds = true
        bodyContainerLayer.addSublayer(sphereLayer)

        // Векторные светящиеся глаза Grok Bot
        sphereLayer.addSublayer(eyesContainerLayer)

        for eye in [leftEyeLayer, rightEyeLayer] {
            eye.shadowOffset = .zero
            eye.shadowRadius = 5.0
            eye.shadowOpacity = 0.85
            eye.lineCap = .round
            eyesContainerLayer.addSublayer(eye)
        }

        // Пользовательская картинка PNG/JPG (перекрывает глаза, если выбрана)
        customImageLayer.contentsGravity = .resizeAspectFill
        customImageLayer.masksToBounds = true
        customImageLayer.contentsScale = scale
        customImageLayer.isHidden = true
        sphereLayer.addSublayer(customImageLayer)

        // Счётчик-бейдж
        badgeBackgroundLayer.borderColor = NSColor.white.cgColor
        badgeBackgroundLayer.borderWidth = 1.5
        badgeBackgroundLayer.isHidden = true
        bodyContainerLayer.addSublayer(badgeBackgroundLayer)

        badgeTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        badgeTextLayer.fontSize = 12
        badgeTextLayer.alignmentMode = .center
        badgeTextLayer.foregroundColor = NSColor.white.cgColor
        badgeTextLayer.contentsScale = scale
        badgeBackgroundLayer.addSublayer(badgeTextLayer)

        // Плашка названия задачи под головой
        subtitleBgLayer.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.88).cgColor
        subtitleBgLayer.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        subtitleBgLayer.borderWidth = 1.0
        subtitleBgLayer.cornerRadius = 6.0
        subtitleBgLayer.isHidden = true
        root.addSublayer(subtitleBgLayer)

        subtitleTextLayer.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitleTextLayer.fontSize = 11
        subtitleTextLayer.alignmentMode = .center
        subtitleTextLayer.truncationMode = .end
        subtitleTextLayer.foregroundColor = NSColor.white.cgColor
        subtitleTextLayer.contentsScale = scale
        subtitleBgLayer.addSublayer(subtitleTextLayer)
    }

    private func headDiameter() -> CGFloat {
        CGFloat(min(max(settings.headSize, 48), 160))
    }

    private func headCenter() -> CGPoint {
        let d = headDiameter()
        // Смещаем центр чуть выше середины, чтобы снизу помещалась подпись задачи
        return CGPoint(x: bounds.midX, y: bounds.height - d / 2.0 - 16.0)
    }

    private func layoutHeadLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let d = headDiameter()
        let center = headCenter()
        let ringSize = d + 12.0

        for ring in [trackRingLayer, activeRingLayer] {
            ring.bounds = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
            ring.position = center
            // Дуга начинается сверху (12 часов) и идёт по часовой стрелке
            let path = CGMutablePath()
            path.addArc(
                center: CGPoint(x: ringSize / 2.0, y: ringSize / 2.0),
                radius: (ringSize - 3.0) / 2.0,
                startAngle: .pi / 2.0,
                endAngle: -.pi * 1.5,
                clockwise: true
            )
            ring.path = path
        }

        bodyContainerLayer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        bodyContainerLayer.position = center
        bodyContainerLayer.shadowPath = CGPath(ellipseIn: bodyContainerLayer.bounds, transform: nil)

        sphereLayer.frame = bodyContainerLayer.bounds
        sphereLayer.cornerRadius = d / 2.0

        customImageLayer.frame = sphereLayer.bounds
        eyesContainerLayer.frame = sphereLayer.bounds

        layoutEyesPaths(diameter: d)
        layoutBadge(diameter: d)
        layoutSubtitle(center: center, diameter: d)
        updateRingProgressAndColors()

        CATransaction.commit()
    }

    private func layoutEyesPaths(diameter d: CGFloat) {
        let hasCustomImage = !customImageLayer.isHidden
        eyesContainerLayer.isHidden = hasCustomImage
        guard !hasCustomImage else { return }

        let leftCenter = CGPoint(x: d * 0.36, y: d * 0.50)
        let rightCenter = CGPoint(x: d * 0.64, y: d * 0.50)
        let eyeW = max(5.0, d * 0.13)
        let eyeH = max(8.0, d * 0.22)

        leftEyeLayer.bounds = CGRect(x: 0, y: 0, width: eyeW * 1.8, height: eyeH * 1.6)
        rightEyeLayer.bounds = leftEyeLayer.bounds
        leftEyeLayer.position = leftCenter
        rightEyeLayer.position = rightCenter

        let boxW = leftEyeLayer.bounds.width
        let boxH = leftEyeLayer.bounds.height

        switch snapshot.aggregateState {
        case .done:
            // Радостные глаза-дуги ^ ^
            let strokeW = max(3.0, d * 0.055)
            for eye in [leftEyeLayer, rightEyeLayer] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: boxW * 0.16, y: boxH * 0.36))
                p.addQuadCurve(
                    to: CGPoint(x: boxW * 0.84, y: boxH * 0.36),
                    control: CGPoint(x: boxW * 0.50, y: boxH * 0.88)
                )
                eye.path = p
                eye.fillColor = nil
                eye.strokeColor = NSColor(calibratedRed: 0.43, green: 0.91, blue: 0.72, alpha: 1.0).cgColor
                eye.lineWidth = strokeW
                eye.shadowColor = NSColor.systemGreen.cgColor
                eye.setAffineTransform(.identity)
            }

        case .error:
            // Грустные опущенные глаза
            let rect = CGRect(
                x: (boxW - eyeW) / 2.0,
                y: (boxH - eyeH * 0.8) / 2.0 - d * 0.02,
                width: eyeW,
                height: eyeH * 0.8
            )
            let oval = CGPath(ellipseIn: rect, transform: nil)
            let sadColor = NSColor(calibratedRed: 0.99, green: 0.60, blue: 0.60, alpha: 1.0).cgColor

            leftEyeLayer.path = oval
            rightEyeLayer.path = oval
            for eye in [leftEyeLayer, rightEyeLayer] {
                eye.fillColor = sadColor
                eye.strokeColor = nil
                eye.shadowColor = NSColor.systemRed.cgColor
            }
            leftEyeLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.34))
            rightEyeLayer.setAffineTransform(CGAffineTransform(rotationAngle: 0.34))

        case .stale:
            // Зависшая задача: прищуренные спокойные серые глаза
            let rect = CGRect(
                x: (boxW - eyeW) / 2.0,
                y: (boxH - eyeH * 0.65) / 2.0,
                width: eyeW,
                height: eyeH * 0.65
            )
            let oval = CGPath(ellipseIn: rect, transform: nil)
            for eye in [leftEyeLayer, rightEyeLayer] {
                eye.path = oval
                eye.fillColor = NSColor.systemGray.cgColor
                eye.strokeColor = nil
                eye.shadowOpacity = 0.2
                eye.setAffineTransform(.identity)
            }

        case .working, .idle:
            // Классические светящиеся овальные глаза Grok Bot
            let rect = CGRect(
                x: (boxW - eyeW) / 2.0,
                y: (boxH - eyeH) / 2.0,
                width: eyeW,
                height: eyeH
            )
            let oval = CGPath(ellipseIn: rect, transform: nil)
            let isWorking = (snapshot.aggregateState == .working)
            let fill = isWorking
                ? NSColor(calibratedRed: 0.52, green: 0.85, blue: 1.0, alpha: 1.0).cgColor
                : NSColor(calibratedWhite: 0.93, alpha: 1.0).cgColor

            for eye in [leftEyeLayer, rightEyeLayer] {
                eye.path = oval
                eye.fillColor = fill
                eye.strokeColor = nil
                eye.shadowColor = NSColor.systemCyan.cgColor
                eye.shadowOpacity = 0.85
                eye.setAffineTransform(.identity)
            }
        }
    }

    private func layoutBadge(diameter d: CGFloat) {
        let show = (snapshot.badgeCount > 0 && snapshot.aggregateState != .idle)
        badgeBackgroundLayer.isHidden = !show
        guard show else { return }

        let text = "\(snapshot.badgeCount)"
        badgeTextLayer.string = text

        let height: CGFloat = 22
        let extra = max(0, text.count - 1)
        let width = max(height, height + CGFloat(extra) * 7)

        switch snapshot.aggregateState {
        case .error:
            badgeBackgroundLayer.backgroundColor = NSColor.systemRed.cgColor
        case .done:
            badgeBackgroundLayer.backgroundColor = NSColor.systemGreen.cgColor
        default:
            badgeBackgroundLayer.backgroundColor = NSColor.systemBlue.cgColor
        }

        badgeBackgroundLayer.frame = CGRect(
            x: d - width + 4,
            y: d - height + 4,
            width: width,
            height: height
        )
        badgeBackgroundLayer.cornerRadius = height / 2.0
        badgeTextLayer.frame = CGRect(x: 0, y: 3, width: width, height: 15)
    }

    private func layoutSubtitle(center: CGPoint, diameter d: CGFloat) {
        guard let title = snapshot.subtitle, !title.isEmpty,
              snapshot.aggregateState == .working || snapshot.aggregateState == .stale || snapshot.aggregateState == .error else {
            subtitleBgLayer.isHidden = true
            return
        }

        subtitleBgLayer.isHidden = false
        subtitleTextLayer.string = title

        let maxW = bounds.width - 10
        let approxW = min(maxW, max(72, CGFloat(title.count) * 7.2 + 18))
        let h: CGFloat = 20
        let y = max(2, center.y - d / 2.0 - h - 8)

        subtitleBgLayer.frame = CGRect(
            x: (bounds.width - approxW) / 2.0,
            y: y,
            width: approxW,
            height: h
        )
        subtitleTextLayer.frame = CGRect(x: 6, y: 2.5, width: approxW - 12, height: 15)
    }

    private func updateRingProgressAndColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch snapshot.aggregateState {
        case .idle:
            trackRingLayer.isHidden = true
            activeRingLayer.isHidden = true

        case .working:
            activeRingLayer.isHidden = false
            activeRingLayer.strokeColor = NSColor.systemCyan.cgColor
            if let prog = snapshot.activeProgress {
                trackRingLayer.isHidden = false
                trackRingLayer.strokeColor = NSColor.systemCyan.withAlphaComponent(0.22).cgColor
                activeRingLayer.removeAnimation(forKey: "grok.spin")
                activeRingLayer.strokeStart = 0.0
                activeRingLayer.strokeEnd = CGFloat(min(max(prog, 0.04), 1.0))
            } else {
                trackRingLayer.isHidden = true
                activeRingLayer.strokeStart = 0.08
                activeRingLayer.strokeEnd = 0.84
                if activeRingLayer.animation(forKey: "grok.spin") == nil {
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                    spin.fromValue = 0.0
                    spin.toValue = -Double.pi * 2.0
                    spin.duration = 2.2
                    spin.repeatCount = .infinity
                    spin.isRemovedOnCompletion = false
                    activeRingLayer.add(spin, forKey: "grok.spin")
                }
            }

        case .stale:
            trackRingLayer.isHidden = true
            activeRingLayer.isHidden = false
            activeRingLayer.removeAllAnimations()
            activeRingLayer.strokeColor = NSColor.systemGray.cgColor
            activeRingLayer.strokeStart = 0.0
            activeRingLayer.strokeEnd = CGFloat(snapshot.activeProgress ?? 1.0)

        case .done:
            trackRingLayer.isHidden = true
            activeRingLayer.isHidden = false
            activeRingLayer.strokeColor = NSColor.systemGreen.cgColor
            activeRingLayer.strokeStart = 0.0
            activeRingLayer.strokeEnd = 1.0

        case .error:
            trackRingLayer.isHidden = true
            activeRingLayer.isHidden = false
            activeRingLayer.removeAllAnimations()
            activeRingLayer.strokeColor = NSColor.systemRed.cgColor
            activeRingLayer.strokeStart = 0.0
            activeRingLayer.strokeEnd = 1.0
        }

        CATransaction.commit()
    }

    // MARK: - Анимации мимики и корпуса

    private func applyAnimationsAndEyeExpression() {
        activeRingLayer.removeAllAnimations()
        bodyContainerLayer.removeAllAnimations()
        eyesContainerLayer.removeAllAnimations()
        leftEyeLayer.removeAllAnimations()
        rightEyeLayer.removeAllAnimations()

        let d = headDiameter()
        layoutEyesPaths(diameter: d)
        updateRingProgressAndColors()

        switch snapshot.aggregateState {
        case .idle:
            bodyContainerLayer.opacity = 0.65
            // Редкое естественное моргание раз в 4.6 с
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1.0, 1.0, 0.08, 1.0]
            blink.keyTimes = [0.0, 0.92, 0.96, 1.0]
            blink.duration = 4.6
            blink.repeatCount = .infinity
            blink.isRemovedOnCompletion = false
            leftEyeLayer.add(blink, forKey: "grok.blink")
            rightEyeLayer.add(blink, forKey: "grok.blink")

        case .working:
            bodyContainerLayer.opacity = 1.0
            // Глаза сканируют влево-вправо
            let shift = max(3.0, d * 0.08)
            let scan = CAKeyframeAnimation(keyPath: "transform.translation.x")
            scan.values = [-shift, shift, -shift]
            scan.keyTimes = [0.0, 0.5, 1.0]
            scan.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut)
            ]
            scan.duration = 1.5
            scan.repeatCount = .infinity
            scan.isRemovedOnCompletion = false
            eyesContainerLayer.add(scan, forKey: "grok.scan")

        case .stale:
            bodyContainerLayer.opacity = 0.85

        case .done:
            bodyContainerLayer.opacity = 1.0

            let ringScale = CABasicAnimation(keyPath: "transform.scale")
            ringScale.fromValue = 0.96
            ringScale.toValue = 1.24

            let ringFade = CABasicAnimation(keyPath: "opacity")
            ringFade.fromValue = 0.85
            ringFade.toValue = 0.0

            let ringGroup = CAAnimationGroup()
            ringGroup.animations = [ringScale, ringFade]
            ringGroup.duration = 1.5
            ringGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ringGroup.repeatCount = .infinity
            ringGroup.isRemovedOnCompletion = false
            activeRingLayer.add(ringGroup, forKey: "grok.done.ring")

            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0.0, 7.0, 0.0, 3.0, 0.0]
            bounce.keyTimes = [0.0, 0.28, 0.55, 0.76, 1.0]
            bounce.duration = 1.6
            bounce.repeatCount = .infinity
            bounce.isRemovedOnCompletion = false
            bodyContainerLayer.add(bounce, forKey: "grok.done.bounce")

        case .error:
            bodyContainerLayer.opacity = 1.0
        }
    }

    private func reloadCustomAvatarIfNeeded() {
        let path = settings.customAvatarPath
        if !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let img = NSImage(contentsOfFile: path) {
            var rect = NSRect(origin: .zero, size: img.size)
            if let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                customImageLayer.contents = cg
                customImageLayer.isHidden = false
                return
            }
        }
        customImageLayer.contents = nil
        customImageLayer.isHidden = true
    }

    // MARK: - Мышь: перетаскивание, одиночный клик, двойной клик (Snooze 1h), правый клик

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
        didDragWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouseLocation.x
        let dy = current.y - initialMouseLocation.y

        if hypot(dx, dy) > 4.0 {
            didDragWindow = true
        }
        if didDragWindow {
            pendingSingleClickWork?.cancel()
            onHoverChanged?(false)
            window.setFrameOrigin(NSPoint(
                x: initialWindowOrigin.x + dx,
                y: initialWindowOrigin.y + dy
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        if didDragWindow {
            onPositionChanged?(window.frame.origin)
            return
        }

        if event.clickCount >= 2 {
            pendingSingleClickWork?.cancel()
            pendingSingleClickWork = nil
            onDoubleClick?()
        } else {
            pendingSingleClickWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onSingleClick?()
            }
            pendingSingleClickWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        pendingSingleClickWork?.cancel()
        onHoverChanged?(false)
        if let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}

// MARK: - Всплывающий поповер при наведении

final class RecentTasksPopoverController: NSViewController {
    private let headerLabel = NSTextField(labelWithString: "")
    private let tasksStack = NSStackView()
    private var cachedTasks: [TrackedTask] = []

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 110))

        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .labelColor

        tasksStack.orientation = .vertical
        tasksStack.alignment = .leading
        tasksStack.spacing = 6

        let rootStack = NSStackView(views: [headerLabel, tasksStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            rootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(equalToConstant: 250)
        ])

        self.view = container
        renderContent()
    }

    func update(tasks: [TrackedTask]) {
        cachedTasks = tasks
        if isViewLoaded {
            renderContent()
        }
    }

    private func renderContent() {
        headerLabel.stringValue = L10n.activeTasksHeader

        for v in tasksStack.arrangedSubviews {
            tasksStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        if cachedTasks.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: L10n.noTasksYet)
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            tasksStack.addArrangedSubview(empty)
            return
        }

        for task in cachedTasks.prefix(5) {
            let statusBadge: String
            switch task.status {
            case .working: statusBadge = "⏳"
            case .stale:   statusBadge = "⏸"
            case .done:    statusBadge = "✓"
            case .error:   statusBadge = "⚠️"
            case .idle:    statusBadge = "•"
            }

            let pct = task.progress.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
            let line = NSTextField(wrappingLabelWithString: "\(statusBadge) \(task.title)\(pct)")
            line.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            line.maximumNumberOfLines = 2
            tasksStack.addArrangedSubview(line)
        }
    }
}
