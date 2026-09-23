import AppKit
import Carbon.HIToolbox

/// A system wide keyboard shortcut, stored as the raw key code plus the
/// modifier flags reported by AppKit.
struct KeyShortcut: Codable, Equatable {
    /// `NSEvent.keyCode`, or -1 when no shortcut is set.
    var keyCode: Int
    /// `NSEvent.ModifierFlags.rawValue` (device independent flags).
    var modifiers: Int
    /// Human readable form such as "⌃⌥M".
    var display: String

    static let none = KeyShortcut(keyCode: -1, modifiers: 0, display: "")

    var isSet: Bool { keyCode >= 0 && !display.isEmpty }

    /// Modifier mask used by `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Global shortcuts that only use ⌘ steal shortcuts from other apps, so
    /// either ⌃ / ⌥ or a function key is required.
    var isAcceptable: Bool {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) || flags.contains(.option) { return true }
        return Self.isFunctionKey(keyCode)
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    /// Builds the display string and modifier flags from a recorded event.
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.keyCode = Int(event.keyCode)
        self.modifiers = Int(flags.rawValue)
        self.display = Self.displayString(for: event)
    }

    init(keyCode: Int, modifiers: Int, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    static func displayString(for event: NSEvent) -> String {
        var result = ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }

        let keyCode = Int(event.keyCode)
        if let name = functionKeyNames[keyCode] {
            return result + name
        }
        switch keyCode {
        case 36: return result + "↩"
        case 48: return result + "⇥"
        case 49: return result + "Space"
        case 51: return result + "⌫"
        case 53: return result + "⎋"
        case 123: return result + "←"
        case 124: return result + "→"
        case 125: return result + "↓"
        case 126: return result + "↑"
        default:
            let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return characters.isEmpty ? result + "Key \(keyCode)" : result + characters
        }
    }

    private static let functionKeyNames: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]
}
