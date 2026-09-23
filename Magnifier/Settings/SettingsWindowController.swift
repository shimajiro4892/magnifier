import AppKit
import SwiftUI

/// Hosts `SettingsView` in a plain AppKit window.
///
/// An agent (menu bar only) app has no app menu, and SwiftUI's `Settings` scene
/// cannot be opened through `showSettingsWindow:` there, so the window is
/// managed directly.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: .shared,
                                                                     permissions: .shared,
                                                                     controller: .shared,
                                                                     launchAtLogin: .shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "拡大鏡の設定"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
