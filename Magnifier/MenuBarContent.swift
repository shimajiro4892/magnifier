import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionMonitor
    @ObservedObject var controller: MagnifierController

    var body: some View {
        Toggle("拡大鏡を有効にする", isOn: $settings.isEnabled)

        if controller.isActive {
            Button("拡大鏡をオフにする") {
                controller.turnOff(reason: "menu")
            }
        }

        Divider()

        Text("起動ボタン: \(settings.mouseButton.label)")
        Text("動作モード: \(settings.triggerMode.shortLabel)")
        Text("拡大範囲: \(Int(settings.regionWidth))×\(Int(settings.regionHeight)) pt / \(settings.zoom, specifier: "%.1f")倍")
        Text("レンズ: \(Int(settings.lensSize.width))×\(Int(settings.lensSize.height)) pt")

        if !permissions.isScreenRecordingGranted {
            Divider()
            Button("⚠️ 画面収録の許可が必要です…") {
                permissions.openScreenRecordingSettings()
            }
        }

        Divider()

        Button("設定…") {
            AppCommands.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("終了") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
