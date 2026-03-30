import SwiftUI
import AppKit
import Combine
import Foundation

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]
    let barCount: Int = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? levels[index] : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [SW.accent, SW.accentBlue.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: max(2, CGFloat(level) * 18))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: level)
            }
        }
        .frame(width: CGFloat(barCount * 6 - 3), height: 20)
    }
}

// MARK: - Recording Overlay Content

struct RecordingOverlayContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var recorder: AudioRecorder
    
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(appState.state == .recording && pulse ? 1.4 : 1.0)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .opacity(appState.state == .processing || appState.state == .typing ? (pulse ? 1.0 : 0.3) : 1.0)

            if appState.state == .recording {
                WaveformView(levels: recorder.audioLevels)
                
                if recorder.isTooQuiet {
                    HStack(spacing: 3) {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 9))
                        Text(L.tr("Low", "Тихо")).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.orange).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                } else if recorder.isTooNoisy {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.badge.exclamationmark").font(.system(size: 9))
                        Text(L.tr("Noise", "Шум")).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.red).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.red.opacity(0.15)))
                }

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                
                cancelButton
            } else if appState.state == .processing || appState.state == .typing {
                Text(appState.state == .processing ? localizedProcessingStage : L.tr("Typing...", "Печать..."))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(statusText).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            
            if let _ = appState.lastError {
                HStack(spacing: 8) {
                    if recorder.isMicrophoneDenied || appState.isMicrophoneDenied {
                        Button {
                            appState.openMicrophoneSettings()
                        } label: {
                            Text(L.tr("Settings", "Настройки"))
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button { appState.clearError() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .fixedSize()
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.black.opacity(0.45))
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .environment(\.colorScheme, .dark)
        .padding(8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var statusColor: Color {
        if let _ = appState.lastError { return .red }
        switch appState.state {
        case .recording: return .red
        case .processing: return .orange
        case .typing: return .blue
        case .idle: return .gray
        }
    }

    private var statusText: String {
        if let error = appState.lastError { return error }
        switch appState.state {
        case .recording: return L.tr("Recording...", "Запись...")
        case .processing: return localizedProcessingStage
        case .typing: return L.tr("Typing...", "Печать...")
        case .idle: return ""
        }
    }

    private var localizedProcessingStage: String {
        switch appState.processingStage {
        case .converting: return L.tr("Converting...", "Конвертация...")
        case .transcribing: return L.tr("Transcribing...", "Транскрибация...")
        case .postProcessing: return L.tr("Post-processing...", "Постобработка...")
        case .none: return ""
        }
    }

    private var cancelButton: some View {
        Button {
            appState.cancelRecording()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int(duration * 10) % 10
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%1d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%1d", minutes, seconds, tenths)
        }
    }
}

// MARK: - Ghost Panel (never becomes key/main — invisible to window manager)

private class GhostPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Floating Overlay Window Controller

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {
    private var panel: NSPanel?
    private let panelWidth: CGFloat = 500
    private let panelHeight: CGFloat = 80
    private let topMargin: CGFloat = 12

    func show(appState: AppState) {
        if panel == nil {
            let content = RecordingOverlayContent(recorder: appState.recorder)
                .environmentObject(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            guard let frame = overlayFrame() else { return }

            let newPanel = GhostPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.animationBehavior = .none
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            newPanel.isMovableByWindowBackground = false
            newPanel.hidesOnDeactivate = false
            newPanel.ignoresMouseEvents = false

            newPanel.contentView = hostingView
            self.panel = newPanel
        }

        if let frame = overlayFrame() {
            panel?.setFrame(frame, display: true)
        }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func overlayFrame() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - (panelWidth / 2)
        let y = visibleFrame.maxY - panelHeight - topMargin
        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
