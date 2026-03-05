import SwiftUI
import Combine
import AVFoundation

// MARK: - App State

enum AppRecordingState: Equatable {
    case idle
    case recording
    case processing
    case typing
}

enum ProcessingStage: String {
    case converting = "Converting..."
    case transcribing = "Transcribing..."
    case postProcessing = "Post-processing..."
    case none = ""
}


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    // MARK: - Published State
    @Published var state: AppRecordingState = .idle
    @Published var processingStage: ProcessingStage = .none
    @Published var settings: AppSettings
    @Published var history: [TranscriptionHistoryEntry] = []
    @Published var lastError: String?
    @Published var lastTranscription: String?

    @Published var copiedFeedback = false
    @Published var availableInputDevices: [AVCaptureDevice] = []

    // Statistics calculated directly from history for accuracy/self-healing
    var totalWords: Int {
        history.filter { !$0.isFromFileImport }
               .reduce(0) { $0 + $1.processedText.split { $0.isWhitespace }.count }
    }
    var totalDuration: TimeInterval {
        history.filter { !$0.isFromFileImport }
               .reduce(0) { $0 + $1.duration }
    }
    var averageWPM: Int {
        let minutes = totalDuration / 60.0
        // Safeguard: only show WPM if we have enough data to be meaningful
        guard minutes > 0.05, totalWords > 0 else { return 0 } 
        return Int(Double(totalWords) / minutes)
    }
    var estimatedTimeSaved: TimeInterval {
        // Average person types at ~40 WPM. Dictation + AI is much faster.
        // Formula: (Words / 40) - (Words / WPM) -> approximated as 2.5x duration
        return totalDuration * 2.5
    }
    @Published var showOverlayWindow = false {
        didSet {
            if !showOverlayWindow {
                errorTimer?.cancel()
                errorTimer = nil
            }
        }
    }
    @Published var isHotkeyTrusted = false
    @Published var isMicrophoneGranted = false
    @Published var isMicrophoneDenied = false
    @Published var isTranslocated = false
    @Published var isRecordingHotkey = false {
        didSet {
            if isRecordingHotkey {
                hotkeyManager.stop()
            } else {
                setupHotkey()
            }
        }
    }

    // MARK: - Services
    let recorder = AudioRecorder()
    let modelManager = ModelManager()
    private let hotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    var overlayCancellables = Set<AnyCancellable>()
    private var errorTimer: AnyCancellable?
    
    // Hold-mode tracking
    private var keyDownTime: Date?
    private var isHoldActive = false

    private init() {
        print("🚀 AppState initializing...")
        self.settings = Storage.shared.loadSettings()
        self.history = Storage.shared.loadHistory()
        print("📦 Settings and History loaded")
        
        // Initial setup
        Task {
            if settings.automaticallyChecksForUpdates {
                print("🔄 Triggering automatic update check")
                GitHubUpdater.shared.checkForUpdates()
            }
        }
        
        checkTranslocation()
        checkAccessibility()
        refreshAvailableDevices()
        
        // Listen for device changes
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAvailableDevices()
        }
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAvailableDevices()
        }
        self.isHotkeyTrusted = hotkeyManager.isTrusted
        self.isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        print("🔑 Hotkey trusted: \(isHotkeyTrusted)")
        print("🎤 Microphone granted: \(isMicrophoneGranted)")
        setupHotkey()
        startPermissionCheckTimer()
        print("✅ AppState init complete")
    }

    private func checkAccessibility() {
        self.isHotkeyTrusted = hotkeyManager.isTrusted
    }

    func refreshAvailableDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        self.availableInputDevices = session.devices
    }

    private func checkTranslocation() {
        // Simple check for App Translocation (security scoping)
        // If the path contains "/AppTranslocation/", it's likely translocated
        let path = Bundle.main.bundlePath
        self.isTranslocated = path.contains("/AppTranslocation/")
        if isTranslocated {
            print("⚠️ App is running in TRANSLOCATED mode. Path: \(path)")
        }
    }

    func clearError() {
        lastError = nil
        errorTimer?.cancel()
        errorTimer = nil
        if state == .idle {
            showOverlayWindow = false
        }
    }

    // MARK: - Settings

    func saveSettings() {
        Storage.shared.saveSettings(settings)
        hotkeyManager.config = settings.hotkeyConfig
    }

    // MARK: - Hotkey Setup

    func reloadHotkeyManager() {
        hotkeyManager.stop()
        setupHotkey()
    }

    private func setupHotkey() {
        hotkeyManager.config = settings.hotkeyConfig
        hotkeyManager.start(
            promptUser: false, // Don't prompt automatically on launch, user triggers via Settings
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )
    }

    func requestAccessibilityPermission() {
        // First check silently — if already trusted, just update state
        if hotkeyManager.isTrusted {
            self.isHotkeyTrusted = true
            reloadHotkeyManager()
            return
        }
        // Not trusted — AXIsProcessTrustedWithOptions(prompt: true) shows the native
        // system dialog with "Deny" / "Open System Settings" buttons.
        // Do NOT manually open System Settings — that causes duplicate windows.
        let trusted = hotkeyManager.checkTrust(prompt: true)
        self.isHotkeyTrusted = trusted
        if trusted {
            reloadHotkeyManager()
        }
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private func startPermissionCheckTimer() {
        // Run every 1 second while in common modes (prevents blocking during UI interaction)
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let trusted = self.hotkeyManager.isTrusted
                if self.isHotkeyTrusted != trusted {
                    self.isHotkeyTrusted = trusted
                    if trusted {
                        // Automatically start manager if it was blocked before
                        self.reloadHotkeyManager()
                    }
                }
                
                let micStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                if self.isMicrophoneGranted != micStatus {
                    self.isMicrophoneGranted = micStatus
                }
                
                let denied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
                if self.isMicrophoneDenied != denied {
                    self.isMicrophoneDenied = denied
                    // Auto-dismiss permission error overlay when access is granted
                    if !denied, let error = self.lastError, error.contains("Microphone access denied") {
                        self.lastError = nil
                        if self.state == .idle {
                            self.showOverlayWindow = false
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Mode Logic

    private func handleKeyDown() {
        switch settings.recordingMode {
        case .hold:
            if state == .idle {
                keyDownTime = Date()
                startRecording()
            }

        case .toggle:
            if state == .recording {
                stopAndTranscribe()
            } else if state == .idle {
                startRecording()
            }

        case .pushToTalk:
            if state == .idle {
                keyDownTime = Date()
                startRecording()
            } else if state == .recording {
                stopAndTranscribe()
            }
        }
    }

    private func handleKeyUp() {
        let now = Date()
        let duration = keyDownTime.map { now.timeIntervalSince($0) } ?? 0
        
        switch settings.recordingMode {
        case .hold:
            if state == .recording {
                // If held more than 0.8s, it's a real recording. 
                // If less, it might be a misclick or the user wants to cancel.
                if duration > 0.8 {
                    stopAndTranscribe()
                } else {
                    cancelRecording()
                }
            }

        case .toggle:
            break

        case .pushToTalk:
            if state == .recording {
                if duration >= 0.8 {
                    // It was a long press (PTT), stop on release
                    stopAndTranscribe()
                } else {
                    // It was a short tap (< 800ms), let it keep recording (Toggle behavior)
                }
            }
        }
        keyDownTime = nil
    }


    // MARK: - Recording Actions

    func startRecording() {
        guard state == .idle else { return }

        // Validate API key for cloud engine
        if settings.engineType == .cloud && settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            showError("No API key configured. Go to Settings → General to add your OpenAI API key.")
            return
        }

        // Validate model for local engine
        if settings.engineType == .local && !modelManager.isModelDownloaded(settings.localModelSize) {
            showError("Model '\(settings.localModelSize.rawValue)' not downloaded. Go to Settings → Engine to download.")
            return
        }

        // Validate Microphone permission - only block if DENIED. 
        // If not determined, recorder.startRecording() will handle the prompt.
        if isMicrophoneDenied { // Using the existing `isMicrophoneDenied` property
            showError("Microphone access denied. Please enable it in System Settings → Privacy & Security.")
            return
        }

        lastError = nil
        state = .recording
        showOverlayWindow = true

        recorder.startRecording(inputDeviceID: settings.selectedInputDeviceID)
    }




    func cancelRecording() {
        _ = recorder.stopRecording()
        recorder.cleanup()
        state = .idle
        showOverlayWindow = false
    }

    func stopAndTranscribe() {
        guard state == .recording else { return }

        let (audioURLOptional, recordingDuration) = recorder.stopRecording()
        guard let audioURL = audioURLOptional else {
            // Recording too short or failed
            state = .idle
            showOverlayWindow = false
            return
        }

        state = .processing
        processingStage = .transcribing

        Task { @MainActor in
            do {
                // Diagnostic: check audio file before sending
                let fileAttrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
                let fileSize = fileAttrs?[.size] as? Int64 ?? 0
                print("whisper_debug: 📁 Audio file for transcription: \(audioURL.lastPathComponent), size: \(fileSize) bytes")
                
                if fileSize < 1000 {
                    print("whisper_debug: ⚠️ WARNING: Audio file is suspiciously small (\(fileSize) bytes)!")
                }
                
                // 1. Transcribe
                let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
                let lang = settings.language == "auto" ? nil : settings.language
                let rawText = try await engine.transcribe(audioURL: audioURL, language: lang, onProgress: nil)
                
                print("whisper_debug: 📝 Raw transcription result: '\(rawText)' (length: \(rawText.count))")

                guard !rawText.isEmpty else {
                   if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showError("No speech detected. Try speaking more clearly or check your microphone.")
                    state = .idle
                    processingStage = .none
                    recorder.cleanup()
                    return
                }
                    state = .idle
                    processingStage = .none
                    showOverlayWindow = true // Keep open to show error
                    recorder.cleanup()
                    return
                }

                // 2. Post-process (if enabled)
                var processedText = rawText
                var usage: UsageLog? = nil
                
                if settings.enablePostProcessing && !settings.selectedMode.systemPrompt.isEmpty {
                    processingStage = .postProcessing
                    do {
                        let processor = PostProcessor(settings: settings)
                        let result = try await processor.process(text: rawText, mode: settings.selectedMode)
                        processedText = result.text
                        
                        // Create usage log only if AI was actually used
                        let totalTokens = result.promptTokens + result.completionTokens
                        if totalTokens > 0 {
                            let engine = settings.postProcessingEngine
                            usage = UsageLog(
                                date: Date(),
                                modeName: settings.selectedMode.name,
                                engine: engine.rawValue,
                                promptTokens: result.promptTokens,
                                completionTokens: result.completionTokens,
                                totalTokens: totalTokens,
                                estimatedCost: UsageLog.estimateCost(prompt: result.promptTokens, completion: result.completionTokens, engine: engine)
                            )
                        }
                    } catch {
                        print("⚠️ AI refinement failed: \(error)")
                        self.showError("AI refinement failed. Using raw text.")
                    }
                }

                // 3. Diarization (if enabled)
                if settings.enableSpeakerDiarization && settings.postProcessingEngine == .openai {
                    processingStage = .postProcessing // reuse stage
                    do {
                        let processor = PostProcessor(settings: settings)
                        let diarizationResult = try await processor.diarize(text: processedText)
                        processedText = diarizationResult.text
                        
                        // Accumulate tokens
                        let currentTokens = (usage?.totalTokens ?? 0) + diarizationResult.promptTokens + diarizationResult.completionTokens
                        let currentPromptTokens = (usage?.promptTokens ?? 0) + diarizationResult.promptTokens
                        let currentCompletionTokens = (usage?.completionTokens ?? 0) + diarizationResult.completionTokens
                        
                        usage = UsageLog(
                            date: Date(),
                            modeName: settings.selectedMode.name,
                            engine: PostProcessingEngine.openai.rawValue,
                            promptTokens: currentPromptTokens,
                            completionTokens: currentCompletionTokens,
                            totalTokens: currentTokens,
                            estimatedCost: UsageLog.estimateCost(prompt: currentPromptTokens, completion: currentCompletionTokens, engine: .openai)
                        )
                    } catch {
                        print("⚠️ Diarization failed: \(error)")
                    }
                }

                // 4. Store result (no auto-clipboard — user copies manually from tray)

                // 5. Hide overlay BEFORE insertion to return focus to target app
                showOverlayWindow = false

                // 6. Insert Result
                if settings.autoTypeResult {
                    state = .typing
                    // Small delay to let system handle window closing and focus return
                    try await Task.sleep(nanoseconds: 50_000_000)
                    AutoTyper.insert(text: processedText, method: settings.insertionMethod)
                    
                    if settings.experimentalAutoEnter {
                        AutoTyper.simulateReturn()
                    }
                }

                // 7. Save to history & usage logs
                // 6. Update Stats
                let wordCount = processedText.split { $0.isWhitespace || $0.isPunctuation }.count
                settings.lifetimeWords += wordCount
                settings.lifetimeDuration += recordingDuration
                saveSettings()

                let entry = TranscriptionHistoryEntry(
                    rawText: rawText,
                    processedText: processedText,
                    modeName: settings.selectedMode.name,
                    duration: recordingDuration,
                    engineUsed: settings.engineType.rawValue + (settings.enablePostProcessing ? " + AI" : "") + (settings.enableSpeakerDiarization ? " + Diarization" : ""),
                    usage: usage
                )
                Storage.shared.addTranscriptionHistoryEntry(entry)
                history.insert(entry, at: 0)
                
                if let u = usage {
                    settings.usageLogs.append(u)
                    cleanupOldLogs()
                }
                saveSettings()

                lastTranscription = processedText

                state = .idle
                processingStage = .none
                recorder.cleanup()


            } catch {
                showError(error.localizedDescription)
                recorder.cleanup()
            }
        }
    }

    func showError(_ message: String) {
        lastError = message
        showOverlayWindow = true
        
        errorTimer?.cancel()
        errorTimer = Just(())
            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.lastError = nil
                self?.showOverlayWindow = false
            }
    }

    // MARK: - Tray toggle (always uses toggle behavior)

    func toggleFromMenuBar() {
        if state == .recording {
            stopAndTranscribe()
        } else if state == .idle {
            startRecording()
        }
    }

    // MARK: - History

    func deleteTranscriptionHistoryEntry(_ entry: TranscriptionHistoryEntry) {
        Storage.shared.deleteTranscriptionHistoryEntry(id: entry.entryId)
        history.removeAll { $0.entryId == entry.entryId }
    }

    func clearHistory() {
        Storage.shared.clearHistory()
        history.removeAll()
    }

    private func cleanupOldLogs() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        settings.usageLogs.removeAll { $0.date < sevenDaysAgo }
    }

}
