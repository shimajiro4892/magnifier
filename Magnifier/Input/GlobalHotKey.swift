import Carbon.HIToolbox
import Foundation

/// Registers a system wide hot key through the Carbon hot key API.
///
/// Unlike a global `NSEvent` key monitor this works without the accessibility
/// permission, and it also works while another app is frontmost.
final class GlobalHotKey {
    /// The Carbon callback has no context pointer of its own, so the active
    /// instance is kept here (only one shortcut is registered at a time).
    private static var current: GlobalHotKey?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPressed: (() -> Void)?

    /// Registers the hot key, replacing any previous registration.
    /// Returns `false` when the combination is already taken by another app.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, onPressed: @escaping () -> Void) -> Bool {
        unregister()
        self.onPressed = onPressed
        Self.current = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            GlobalHotKey.current?.fire()
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        guard handlerStatus == noErr else {
            Log.input.error("hot key handler install failed: \(handlerStatus, privacy: .public)")
            unregister()
            return false
        }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D474E31), id: 1) // 'MGN1'
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        guard status == noErr, let reference else {
            Log.input.error("hot key registration failed: \(status, privacy: .public)")
            unregister()
            return false
        }

        hotKeyRef = reference
        Log.input.info("hot key registered keyCode=\(keyCode, privacy: .public) modifiers=\(modifiers, privacy: .public)")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            Log.input.info("hot key unregistered")
        }
        hotKeyRef = nil
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        onPressed = nil
        if Self.current === self {
            Self.current = nil
        }
    }

    private func fire() {
        onPressed?()
    }
}
