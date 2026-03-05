import SwiftUI
import Carbon

struct HotkeyRecorderView: View {
    @EnvironmentObject var appState: AppState
    @Binding var config: HotkeyConfig
    @State private var tempConfig: HotkeyConfig?
    
    var body: some View {
        HStack {
            Text("Global Hotkey")
            Spacer()
            
            Button {
                startRecording()
            } label: {
                Text(appState.isRecordingHotkey ? "Press keys..." : config.displayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appState.isRecordingHotkey ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(appState.isRecordingHotkey ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .background(KeyEventView(isRecording: $appState.isRecordingHotkey, onKeyRecorded: { newConfig in
                config = newConfig
                appState.isRecordingHotkey = false
            }))
            
            if !appState.isRecordingHotkey {

                Button {
                    config = HotkeyConfig() // Default: Opt+Space
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to defaults")
            }
        }
    }
    
    private func startRecording() {
        appState.isRecordingHotkey = true
    }
}

/// Invisible view that captures key events when focused
struct KeyEventView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyRecorded: (HotkeyConfig) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = RecordingNSView()
        view.isRecording = isRecording
        view.onKeyRecorded = onKeyRecorded
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? RecordingNSView {
            view.isRecording = isRecording
            if isRecording {
                // Ensure the app is active and this view is first responder to catch keys
                NSApp.activate(ignoringOtherApps: true)
                view.window?.makeKeyAndOrderFront(nil)
                view.window?.makeFirstResponder(view)
            }
        }
    }
    
    class RecordingNSView: NSView {
        var isRecording = false
        var onKeyRecorded: ((HotkeyConfig) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            
            let keyCode = Int(event.keyCode)
            let isModifierOnly = [54, 55, 56, 57, 58, 59, 60, 61, 62].contains(keyCode)
            
            if isModifierOnly {
                return
            }
            
            let flags = event.modifierFlags
            let newConfig = HotkeyConfig(
                keyCode: keyCode,
                useOption: flags.contains(.option),
                useCommand: flags.contains(.command),
                useControl: flags.contains(.control),
                useShift: flags.contains(.shift)
            )
            
            onKeyRecorded?(newConfig)
        }
    }
}
