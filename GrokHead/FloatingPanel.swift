import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        applyCaptureAndFullscreenPolicy(autoHideFullscreenAndCapture: false)
    }

    func applyCaptureAndFullscreenPolicy(autoHideFullscreenAndCapture: Bool) {
        if autoHideFullscreenAndCapture {
            // Скрывать окно на записи экрана и демонстрации экрана (Zoom / Meet / OBS)
            sharingType = .none
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        } else {
            sharingType = .readOnly
            collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
