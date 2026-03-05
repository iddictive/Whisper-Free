import SwiftUI
import AppKit
import Combine
import Foundation

@main
struct WhisperFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    init() {
        print("🚀 WhisperKillerApp initializing...")
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView()
                .environmentObject(appState)
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
        print("🚀 applicationDidFinishLaunching...")
        
        // Ensure app can run without dock icon but with menu bar
        NSApp.setActivationPolicy(.accessory)
        
        // Bridge AppState.showOverlayWindow → OverlayWindowController
        let appState = AppState.shared
        appState.$showOverlayWindow
            .sink { [weak self] show in
                guard let self = self else { return }
                if show {
                    self.overlayController.show(appState: appState)
                } else {
                    self.overlayController.hide()
                }
            }
            .store(in: &appState.overlayCancellables)
        
        // Show setup wizard if needed
        if !appState.settings.setupCompleted {
            print("🪄 Showing Setup Wizard...")
            showSetupWizard()
        }
        print("✨ Launch sequence complete")
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
        window.title = "WhisperKiller Settings"
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
    @EnvironmentObject var appState: AppState
    @State private var pulseOpacity: CGFloat = 1.0
    @State private var timer: Timer?
    @State private var pulseUp = false
    
    var body: some View {
        Image(nsImage: createMenuImage())
            .onAppear { startPulse() }
            .onChange(of: appState.state) { _, _ in startPulse() }
    }
    
    private var isAnimated: Bool {
        appState.state == .recording || appState.state == .processing
    }
    
    private func startPulse() {
        timer?.invalidate()
        if isAnimated {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    if pulseUp {
                        pulseOpacity += 0.04
                        if pulseOpacity >= 1.0 { pulseUp = false }
                    } else {
                        pulseOpacity -= 0.04
                        if pulseOpacity <= 0.3 { pulseUp = true }
                    }
                }
            }
        } else {
            pulseOpacity = 1.0
        }
    }
    
    private var dotColor: NSColor {
        switch appState.state {
        case .recording: return .systemRed
        case .processing: return .systemOrange
        default: return .clear
        }
    }
    
    private func createMenuImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let isMonochrome = appState.settings.useMonochromeMenuIcon
        let image = NSImage(size: size)
        image.lockFocus()
        
        if isMonochrome {
            // SF Symbol for native monochrome look
            if let sfImage = NSImage(systemSymbolName: "microphone.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let configured = sfImage.withSymbolConfiguration(config) ?? sfImage
                let sfSize = configured.size
                let x = (size.width - sfSize.width) / 2
                let y = (size.height - sfSize.height) / 2
                configured.draw(in: NSRect(x: x, y: y, width: sfSize.width, height: sfSize.height),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        } else {
            // Colored app icon
            if let icon = NSApp.applicationIconImage {
                let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }
        
        // Draw status dot ONLY during recording or processing (skip in monochrome — isTemplate kills colors)
        if !isMonochrome && (appState.state == .recording || appState.state == .processing) {
            let dotSize: CGFloat = 6
            let dotX = size.width - dotSize - 1
            let dotY: CGFloat = 1
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.5, dy: -0.5)).fill()
            
            let opacity = appState.state == .processing ? pulseOpacity : 1.0
            dotColor.withAlphaComponent(opacity).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
        
        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }
}
