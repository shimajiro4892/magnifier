import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        Form {
            if !permissions.isScreenRecordingGranted {
                Section {
                    PermissionBanner(permissions: permissions)
                }
            }

            Section("動作") {
                Toggle("拡大鏡を有効にする", isOn: $settings.isEnabled)
                Picker("起動ボタン", selection: $settings.mouseButton) {
                    ForEach(MouseButtonChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Picker("動作モード", selection: $settings.triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("トグル: ボタンを押すたびに表示 / 非表示を切り替えます。押している間: ボタンを押している間だけ表示します。どちらもクリックは背面のアプリにそのまま届きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("拡大する範囲") {
                LabeledSlider(title: "横", value: $settings.regionWidth, range: 40...800, unit: "pt")
                LabeledSlider(title: "縦", value: $settings.regionHeight, range: 40...800, unit: "pt")
                LabeledSlider(title: "倍率", value: $settings.zoom, range: 1...10, unit: "倍", decimals: 1)
                LabeledRow(title: "レンズの大きさ",
                           value: "\(Int(settings.lensSize.width)) × \(Int(settings.lensSize.height)) pt")
                Text("「拡大する範囲」は元の画面上の大きさ、レンズの大きさは 範囲 × 倍率 です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("表示") {
                Picker("形状", selection: $settings.shape) {
                    ForEach(LensShape.allCases) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                Toggle("カーソルを拡大表示に含める", isOn: $settings.showsCursor)
                Toggle("なめらかに拡大（オフでドット感）", isOn: $settings.smoothScaling)
                Toggle("枠線を表示", isOn: $settings.showBorder)
                Toggle("画面の外にはみ出さない", isOn: $settings.clampToScreen)
                LabeledSlider(title: "表示位置のずれ X", value: $settings.offsetX, range: -400...400, unit: "pt")
                LabeledSlider(title: "表示位置のずれ Y", value: $settings.offsetY, range: -400...400, unit: "pt")
                Text("ずれを設定するとレンズをカーソルから離して表示できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("キャプチャ") {
                Picker("フレームレート", selection: $settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                Text("フレームレートとカーソル表示の変更は、次にボタンを押したときから反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .navigationTitle("拡大鏡の設定")
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var decimals: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.\(decimals)f%@", value, unit))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct PermissionBanner: View {
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("画面収録の許可が必要です", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("システム設定 → プライバシーとセキュリティ → 画面収録 で「拡大鏡」を有効にしてください。許可したあとはアプリの再起動が必要です。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("システム設定を開く") {
                    permissions.openScreenRecordingSettings()
                }
                Button("再起動") {
                    permissions.relaunchApp()
                }
            }
        }
        .padding(.vertical, 4)
    }
}
