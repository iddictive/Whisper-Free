import SwiftUI
import Combine
import AppKit

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Static reference so views can access the delegate directly
    static var shared: AppDelegate!

    private var setupWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var overlayController = OverlayWindowController()
    private var cancellables = Set<AnyCancellable>()

    private var appState: AppState { AppState.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // Single instance check
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        
        let otherInstances = runningApps.filter { app in
            // Must have same bundle ID (if exists) or same process name, and NOT be current PID
            let matchingID = app.bundleIdentifier == Bundle.main.bundleIdentifier && app.bundleIdentifier != nil
            let matchingName = app.localizedName == "WhisperFree"
            return (matchingID || matchingName) && app.processIdentifier != currentPID
        }
        
        if !otherInstances.isEmpty {
            print("⚠️ Another instance of WhisperFree is already running (PIDs: \(otherInstances.map { $0.processIdentifier })). Exiting.")
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        // Overlay observer
        appState.$showOverlayWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.overlayController.show(appState: self.appState)
                } else {
                    self.overlayController.hide()
                }
            }
            .store(in: &cancellables)

        // Auto-open setup wizard on first launch
        if !appState.settings.setupCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showSetupWizard()
            }
        } else {
            // Check for updates if setup is done
            GitHubUpdater.shared.checkForUpdates()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Release all modifiers to prevent "stuck" keys if app crashes or closes during typing
        AutoTyper.releaseModifiers()
    }

    func showSetupWizard() {
        if let existing = setupWindowController?.window, existing.isVisible {
            activateForWindow(existing)
            return
        }

        let view = SetupWizardView(modelManager: appState.modelManager) { [weak self] in
            self?.setupWindowController?.close()
            self?.setupWindowController = nil
            self?.deactivateIfNoWindows()
        }
        .environmentObject(appState)

        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.title = "Whisper Free Setup"
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.12, alpha: 1.0)
        win.setContentSize(NSSize(width: 580, height: 600))
        win.center()
        win.level = .floating
        win.hidesOnDeactivate = false
        win.delegate = self

        setupWindowController = NSWindowController(window: win)
        setupWindowController?.showWindow(nil)
        activateForWindow(win)
    }

    func showSettings() {
        if let existing = settingsWindowController?.window, existing.isVisible {
            activateForWindow(existing)
            return
        }

        let view = SettingsView()
            .environmentObject(appState)

        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.title = "Whisper Free Settings"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 950, height: 700))
        win.minSize = NSSize(width: 800, height: 600)
        win.center()
        win.delegate = self

        settingsWindowController = NSWindowController(window: win)
        settingsWindowController?.showWindow(nil)
        activateForWindow(win)
    }

    func showHistory() {
        if let existing = historyWindowController?.window, existing.isVisible {
            activateForWindow(existing)
            return
        }

        let view = HistoryView()
            .environmentObject(appState)
            .frame(minWidth: 480, minHeight: 400)

        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.title = "Transcription History"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 520, height: 460))
        win.center()
        win.delegate = self

        historyWindowController = NSWindowController(window: win)
        historyWindowController?.showWindow(nil)
        activateForWindow(win)
    }

    // MARK: - Activation Policy Management

    /// Bring a specific window to front without causing flicker.
    /// Only switches to .regular once; subsequent calls just focus the window.
    private func activateForWindow(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// When all managed windows are closed, hide the app from Cmd-Tab
    private func deactivateIfNoWindows() {
        let hasSettings = settingsWindowController?.window?.isVisible == true
        let hasHistory = historyWindowController?.window?.isVisible == true
        let hasSetup = setupWindowController?.window?.isVisible == true

        if !hasSettings && !hasHistory && !hasSetup {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindowController?.window {
            settingsWindowController = nil
        } else if window === historyWindowController?.window {
            historyWindowController = nil
        } else if window === setupWindowController?.window {
            setupWindowController = nil
        }

        // Return to accessory mode (invisible in Cmd-Tab) when all windows are closed
        DispatchQueue.main.async { [weak self] in
            self?.deactivateIfNoWindows()
        }
    }
}

// MARK: - Main App

@main
struct WhisperFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

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
                // Fallback (should not happen in production bundle)
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
            if let color = statusColor {
                Circle()
                    .fill(color)
                    .frame(width: 5.0, height: 5.0)
                    .overlay(Circle().stroke(Color.black, lineWidth: 0.5))
                    .offset(x: 6.5, y: 5.5)
                    // Pulse or Blink depending on state
                    .opacity((state == .processing || state == .typing) && !blink ? 0.4 : 1.0)
            }
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
