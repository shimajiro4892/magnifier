import AppKit
import Combine
import CoreGraphics

/// Keeps track of the screen recording permission required by ScreenCaptureKit.
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()

    @Published private(set) var isScreenRecordingGranted: Bool

    private var timer: Timer?

    private init() {
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func startMonitoring() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != isScreenRecordingGranted {
            isScreenRecordingGranted = granted
            Log.app.info("screen recording permission granted=\(granted, privacy: .public)")
        }
    }

    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        return granted
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Screen recording permission only takes effect after a relaunch.
    func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
