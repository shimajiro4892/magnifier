import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MagnifierController.shared.start()

        // Ask for the screen recording permission up front so the system prompt
        // appears before the first button press.
        if !PermissionMonitor.shared.isScreenRecordingGranted {
            PermissionMonitor.shared.requestScreenRecordingAccess()
        }

        let arguments = CommandLine.arguments
        Log.app.info("launch arguments: \(arguments.joined(separator: " "), privacy: .public)")
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                AppCommands.openSettings()
            }
        }
        if arguments.contains("--activate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                MagnifierController.shared.activateForTesting(duration: 8)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MagnifierController.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum AppCommands {
    /// Opens the SwiftUI settings window from an agent (menu bar only) app.
    static func openSettings() {
        NSApp.activate()
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
