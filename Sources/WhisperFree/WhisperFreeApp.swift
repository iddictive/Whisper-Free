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
            Image(systemName: menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch appState.state {
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .typing: return "keyboard"
        case .idle: return "mic"
        }
    }
}
