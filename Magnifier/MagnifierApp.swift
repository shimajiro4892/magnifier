import AppKit
import SwiftUI

@main
struct MagnifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var permissions = PermissionMonitor.shared
    @StateObject private var controller = MagnifierController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(settings: settings, permissions: permissions, controller: controller)
        } label: {
            Image(systemName: controller.isActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
        }
        .menuBarExtraStyle(.menu)
    }
}
