import Combine
import Foundation
import ServiceManagement

/// Login item registration through `SMAppService` (macOS 13+).
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var requiresApproval: Bool
    @Published private(set) var lastError: String?

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
        requiresApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("login item \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            Log.app.error("login item update failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
