import AppKit

/// Borderless, click-through window that hosts the magnifier lens above every other window,
/// including full screen apps and other spaces.
final class OverlayWindow: NSWindow {
    /// Just above the menu bar / status window level.
    static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false
        animationBehavior = .none
        // Keep the overlay out of any screen capture, including our own.
        sharingType = .none
    }
}

/// Plain host view for the lens layers. Never receives events.
final class OverlayHostView: NSView {
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
