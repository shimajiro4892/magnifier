import AppKit

/// Watches for presses of the configured mouse button anywhere on the system.
///
/// Global event monitors are listen-only: they never swallow the event, so the
/// underlying application still receives its normal clicks.
@MainActor
final class MouseButtonMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private(set) var button: MouseButtonChoice = .middle
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let mask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
    ]

    func start(button: MouseButtonChoice) {
        stop()
        self.button = button

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { [weak self] event in
            let type = event.type
            let buttonNumber = event.buttonNumber
            Task { @MainActor in
                self?.handle(type: type, buttonNumber: buttonNumber)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            let type = event.type
            let buttonNumber = event.buttonNumber
            Task { @MainActor in
                self?.handle(type: type, buttonNumber: buttonNumber)
            }
            return event
        }

        Log.input.info("watching button=\(button.shortLabel, privacy: .public)")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Current physical state of the watched button (works without any event delivery).
    var isButtonPressed: Bool {
        (NSEvent.pressedMouseButtons & button.pressedMaskBit) != 0
    }

    private func handle(type: NSEvent.EventType, buttonNumber: Int) {
        guard matches(type: type, buttonNumber: buttonNumber) else { return }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onPress?()
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            onRelease?()
        default:
            break
        }
    }

    private func matches(type: NSEvent.EventType, buttonNumber: Int) -> Bool {
        switch button {
        case .left:
            return type == .leftMouseDown || type == .leftMouseUp
        case .right:
            return type == .rightMouseDown || type == .rightMouseUp
        case .middle, .button4, .button5:
            guard type == .otherMouseDown || type == .otherMouseUp else { return false }
            return buttonNumber == button.rawValue
        }
    }
}
