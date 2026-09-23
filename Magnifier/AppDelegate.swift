import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MagnifierController.shared.start()

        // Ask for the screen recording permission up front so the system prompt
        // appears before the first button press.
        if !PermissionMonitor.shared.isScreenRecordingGranted {
            PermissionMonitor.shared.requestScreenRecordingAccess()
        }
        Log.app.info("screen recording granted=\(PermissionMonitor.shared.isScreenRecordingGranted, privacy: .public)")

        let arguments = CommandLine.arguments
        Log.app.info("launch arguments: \(arguments.joined(separator: " "), privacy: .public)")
        if arguments.contains("--toggle-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    MagnifierController.shared.simulateButtonPress()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    Task { @MainActor in
                        MagnifierController.shared.simulateButtonPress()
                    }
                }
            }
        }
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Task { @MainActor in
                    AppCommands.openSettings()
                }
            }
        }
        if arguments.contains("--activate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    MagnifierController.shared.activateForTesting(duration: 8)
                }
            }
        }
        if arguments.contains("--overlay-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    MagnifierController.shared.activateForTesting(duration: 20, capture: false)
                }
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
    /// Opens the settings window from an agent (menu bar only) app.
    @MainActor
    static func openSettings() {
        SettingsWindowController.shared.show()
    }
}
