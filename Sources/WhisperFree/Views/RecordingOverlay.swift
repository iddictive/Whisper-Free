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
                        Text("Low").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.orange).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                } else if recorder.isTooNoisy {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.badge.exclamationmark").font(.system(size: 9))
                        Text("Noise").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.red).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.red.opacity(0.15)))
                }

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else if appState.state == .processing || appState.state == .typing {
                Text(appState.state == .processing ? appState.processingStage.rawValue : "Typing...")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(statusText).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            
            if let _ = appState.lastError {
                Button { appState.clearError() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .fixedSize()
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.black.opacity(0.45))
                Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
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
        case .recording: return "Recording..."
        case .processing: return appState.processingStage.rawValue
        case .typing: return "Typing..."
        case .idle: return ""
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

// MARK: - Floating Overlay Window Controller

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {
    private var panel: NSPanel?

    func show(appState: AppState) {
        if panel != nil { return }

        let content = RecordingOverlayContent(recorder: appState.recorder)
            .environmentObject(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        guard let screen = NSScreen.main else { return }
        let panelWidth: CGFloat = 500
        let panelHeight: CGFloat = 80
        let safeTop = screen.frame.maxY - screen.visibleFrame.maxY
        let x = screen.frame.midX - (panelWidth / 2)
        let y = screen.frame.maxY - panelHeight - safeTop // Moved closer to notch

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        panel.contentView = hostingView
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
