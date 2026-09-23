import AppKit
import SwiftUI

/// Records a global shortcut from the keyboard.
///
/// The recorder uses a local event monitor while the settings window is key, so
/// no accessibility permission is required.
struct ShortcutRecorder: View {
    @ObservedObject var settings: SettingsStore
    var registrationError: String?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("ショートカット")
                    .frame(width: 120, alignment: .leading)
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecording ? "キーを押してください…" : (settings.hotKey.isSet ? settings.hotKey.display : "未設定"))
                        .frame(minWidth: 150)
                }
                if settings.hotKey.isSet && !isRecording {
                    Button("クリア") {
                        settings.hotKey = .none
                    }
                }
                Spacer()
            }

            if isRecording {
                Text("⌃ または ⌥ を含む組み合わせ、もしくは F1〜F20 を押してください（Esc でキャンセル）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let registrationError {
                Text(registrationError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("押すたびに拡大鏡の表示 / 非表示を切り替えます。他のアプリと競合しない組み合わせを選んでください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let shortcut = KeyShortcut(event: event)
            guard shortcut.isAcceptable else {
                NSSound.beep()
                return nil
            }

            settings.hotKey = shortcut
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
