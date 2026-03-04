import SwiftUI
import AppKit
import Combine
import Foundation

@main
struct WhisperFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    init() {
        // Ensure app can run without dock icon but with menu bar
        NSApp.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView(state: appState.state)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static private(set) var shared: AppDelegate?
    
    private var overlayController = OverlayWindowController()
    private var setupWizardController: SetupWizardWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Show setup wizard if needed
        if !AppState.shared.settings.setupCompleted {
            showSetupWizard()
        }
    }
    
    func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardWindowController()
        }
        setupWizardController?.show()
    }
    
    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }
    
    func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.show()
    }
}

// MARK: - Window Controllers

@MainActor
final class SetupWizardWindowController: NSObject {
    private var window: NSWindow?
    
    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = SetupWizardView(
            modelManager: AppState.shared.modelManager,
            onComplete: { [weak self] in
                self?.close()
            }
        ).environmentObject(AppState.shared)
        
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
        window = nil
    }
}

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    
    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = SettingsView().environmentObject(AppState.shared)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = "WhisperFree Settings"
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class HistoryWindowController: NSObject {
    private var window: NSWindow?
    
    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = HistoryView().environmentObject(AppState.shared)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = "Transcription History"
        window.isReleasedWhenClosed = false
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIconView: View {
    let state: AppRecordingState
    @State private var blink = false
    
    var body: some View {
        ZStack {
            // Main App Icon (Spoof Style)
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: createMenuImage(from: icon))
                    .font(.system(size: 14, weight: .medium))
            } else {
                // Fallback
                Image(systemName: "microphone.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state == .recording ? .red : .primary)
            }
            
            // "Flame/Lightning" indicator for AI activity (Sparkle)
            if state == .processing {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .offset(x: -8, y: -4)
                    .scaleEffect(blink ? 1.2 : 0.8)
                    .opacity(blink ? 1.0 : 0.4)
            }
            
            // Status Dot Overlay (Spoof Style)
            let color = statusColor
            ZStack {
                // White "Halo" for contrast
                Circle()
                    .fill(Color.white)
                    .frame(width: 6.5, height: 6.5)
                
                Circle()
                    .fill(color ?? Color.green) // Spoof uses green for active/running
                    .frame(width: 4.5, height: 4.5)
            }
            .offset(x: 6.0, y: 6.0)
            // Pulse/Blink only during processing
            .opacity(state == .processing || state == .typing ? (blink ? 1.0 : 0.4) : 1.0)
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: state) { _, _ in
            startAnimation()
        }
    }
    
    private func createMenuImage(from icon: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size), 
                 from: .zero, 
                 operation: .sourceOver, 
                 fraction: 1.0)
        image.unlockFocus()
        image.isTemplate = false // Keep original colors
        return image
    }

    private func startAnimation() {
        if state == .processing || state == .typing {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                blink = true
            }
        } else {
            blink = false
        }
    }
    
    private var statusColor: Color? {
        switch state {
        case .recording: return .red
        case .processing: return .orange
        case .typing: return SW.accent
        case .idle: return nil
        }
    }
}
