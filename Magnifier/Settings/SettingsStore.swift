import AppKit
import Combine
import Foundation

/// Mouse buttons that can trigger the magnifier.
enum MouseButtonChoice: Int, CaseIterable, Identifiable {
    case left = 0
    case right = 1
    case middle = 2
    case button4 = 3
    case button5 = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .left: return "左ボタン"
        case .right: return "右ボタン"
        case .middle: return "中ボタン（ホイールクリック）"
        case .button4: return "ボタン4（戻る）"
        case .button5: return "ボタン5（進む）"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        case .middle: return "中"
        case .button4: return "ボタン4"
        case .button5: return "ボタン5"
        }
    }

    /// Bit used by `NSEvent.pressedMouseButtons`.
    var pressedMaskBit: Int { 1 << rawValue }
}

enum LensShape: Int, CaseIterable, Identifiable {
    case circle = 0
    case roundedRect = 1
    case rect = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .circle: return "円"
        case .roundedRect: return "角丸長方形"
        case .rect: return "長方形"
        }
    }
}

/// How the mouse button controls the magnifier.
enum TriggerMode: Int, CaseIterable, Identifiable {
    case toggle = 0
    case hold = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .toggle: return "押すたびに On / Off（トグル）"
        case .hold: return "押している間だけ表示"
        }
    }

    var shortLabel: String {
        switch self {
        case .toggle: return "トグル"
        case .hold: return "押している間"
        }
    }
}

/// User defaults backed settings shared by the UI and the magnifier engine.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var isEnabled: Bool { didSet { persist(isEnabled, .isEnabled) } }
    @Published var mouseButton: MouseButtonChoice { didSet { persist(mouseButton.rawValue, .mouseButton) } }
    @Published var triggerMode: TriggerMode { didSet { persist(triggerMode.rawValue, .triggerMode) } }
    @Published var regionWidth: Double { didSet { persist(regionWidth, .regionWidth) } }
    @Published var regionHeight: Double { didSet { persist(regionHeight, .regionHeight) } }
    @Published var zoom: Double { didSet { persist(zoom, .zoom) } }
    @Published var shape: LensShape { didSet { persist(shape.rawValue, .shape) } }
    @Published var showsCursor: Bool { didSet { persist(showsCursor, .showsCursor) } }
    @Published var smoothScaling: Bool { didSet { persist(smoothScaling, .smoothScaling) } }
    @Published var showBorder: Bool { didSet { persist(showBorder, .showBorder) } }
    @Published var clampToScreen: Bool { didSet { persist(clampToScreen, .clampToScreen) } }
    @Published var offsetX: Double { didSet { persist(offsetX, .offsetX) } }
    @Published var offsetY: Double { didSet { persist(offsetY, .offsetY) } }
    @Published var frameRate: Int { didSet { persist(frameRate, .frameRate) } }

    /// Size of the lens on screen, in points.
    var lensSize: CGSize {
        CGSize(width: max(20, regionWidth * zoom), height: max(20, regionHeight * zoom))
    }

    private enum Key: String {
        case isEnabled, mouseButton, triggerMode, regionWidth, regionHeight, zoom, shape
        case showsCursor, smoothScaling, showBorder, clampToScreen, offsetX, offsetY, frameRate
    }

    private let defaults = UserDefaults.standard

    private init() {
        let store = UserDefaults.standard
        isEnabled = store.object(forKey: Key.isEnabled.rawValue) as? Bool ?? true
        mouseButton = Self.enumValue(store, .mouseButton, default: .middle)
        triggerMode = Self.enumValue(store, .triggerMode, default: .toggle)
        regionWidth = store.object(forKey: Key.regionWidth.rawValue) as? Double ?? 180
        regionHeight = store.object(forKey: Key.regionHeight.rawValue) as? Double ?? 120
        zoom = store.object(forKey: Key.zoom.rawValue) as? Double ?? 2.5
        shape = Self.enumValue(store, .shape, default: .roundedRect)
        showsCursor = store.object(forKey: Key.showsCursor.rawValue) as? Bool ?? true
        smoothScaling = store.object(forKey: Key.smoothScaling.rawValue) as? Bool ?? true
        showBorder = store.object(forKey: Key.showBorder.rawValue) as? Bool ?? true
        clampToScreen = store.object(forKey: Key.clampToScreen.rawValue) as? Bool ?? true
        offsetX = store.object(forKey: Key.offsetX.rawValue) as? Double ?? 0
        offsetY = store.object(forKey: Key.offsetY.rawValue) as? Double ?? 0
        frameRate = store.object(forKey: Key.frameRate.rawValue) as? Int ?? 60
    }

    private static func enumValue<T: RawRepresentable>(_ store: UserDefaults, _ key: Key, default defaultValue: T) -> T where T.RawValue == Int {
        guard let raw = store.object(forKey: key.rawValue) as? Int, let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    private func persist(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
