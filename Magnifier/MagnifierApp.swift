import AppKit
import SwiftUI

@main
struct MagnifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var permissions = PermissionMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(settings: settings, permissions: permissions)
        } label: {
            Image(systemName: settings.isEnabled ? "magnifyingglass" : "magnifyingglass.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
