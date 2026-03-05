import SwiftUI
import Combine

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

struct BackgroundJob: Identifiable, Equatable {
    let id: UUID
    let name: String
    var progress: Float
    var isPaused: Bool
    var engine: TranscriptionEngine?

    static func == (lhs: BackgroundJob, rhs: BackgroundJob) -> Bool {
        lhs.id == rhs.id && lhs.progress == rhs.progress && lhs.isPaused == rhs.isPaused
    }
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
    @Published var backgroundJobs: [BackgroundJob] = []
    @Published var copiedFeedback = false
    @Published var showOverlayWindow = false
    @Published var isHotkeyTrusted = false
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
        self.isHotkeyTrusted = hotkeyManager.isTrusted
        print("🔑 Hotkey trusted: \(isHotkeyTrusted)")
        setupHotkey()
        startPermissionCheckTimer()
        print("✅ AppState init complete")
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
        let trusted = hotkeyManager.checkTrust(prompt: true)
        self.isHotkeyTrusted = trusted
        if trusted {
            reloadHotkeyManager()
        }
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
        if settings.engineType == .cloud && settings.apiKey.isEmpty {
            lastError = "No API key configured. Go to Settings → General to add your OpenAI API key."
            showOverlayWindow = true
            return
        }

        // Validate model for local engine
        if settings.engineType == .local && !modelManager.isModelDownloaded(settings.localModelSize) {
            lastError = "Model '\(settings.localModelSize.rawValue)' not downloaded. Go to Settings → Engine to download."
            showOverlayWindow = true
            return
        }

        lastError = nil
        state = .recording
        showOverlayWindow = true
        pauseBackgroundJobs()
        recorder.startRecording()
    }

    private func pauseBackgroundJobs() {
        for i in 0..<backgroundJobs.count {
            if !backgroundJobs[i].isPaused {
                backgroundJobs[i].isPaused = true
                backgroundJobs[i].engine?.pause()
            }
        }
    }

    private func resumeBackgroundJobs() {
        for i in 0..<backgroundJobs.count {
            if backgroundJobs[i].isPaused {
                backgroundJobs[i].isPaused = false
                backgroundJobs[i].engine?.resume()
            }
        }
    }


    func cancelRecording() {
        _ = recorder.stopRecording()
        recorder.cleanup()
        state = .idle
        showOverlayWindow = false
        resumeBackgroundJobs()
    }

    func stopAndTranscribe() {
        guard state == .recording else { return }

        guard let audioURL = recorder.stopRecording() else {
            // Recording too short
            state = .idle
            showOverlayWindow = false
            return
        }

        state = .processing
        processingStage = .transcribing
        let recordingDuration = recorder.recordingDuration

        Task { @MainActor in
            do {
                // 1. Transcribe
                let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
                let lang = settings.language == "auto" ? nil : settings.language
                let rawText = try await engine.transcribe(audioURL: audioURL, language: lang)

                guard !rawText.isEmpty else {
                    lastError = "No speech detected. Try speaking more clearly or check your microphone."
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
                        // Log error but STILL use raw text as fallback
                        self.lastError = "AI refinement failed: \(error.localizedDescription). Using raw transcription."
                        print("Post-processing error: \(error)")
                    }
                }

                // 4. Store result (no auto-clipboard — user copies manually from tray)

                // 5. Hide overlay BEFORE insertion to return focus to target app
                showOverlayWindow = false

                // 6. Insert Result
                if settings.autoTypeResult {
                    state = .typing
                    // Small delay to let system handle window closing and focus return
                    try await Task.sleep(nanoseconds: 150_000_000)
                    AutoTyper.insert(text: processedText, method: settings.insertionMethod)
                    
                    if settings.experimentalAutoEnter {
                        AutoTyper.simulateReturn()
                    }
                }

                // 7. Save to history & usage logs
                let entry = TranscriptionHistoryEntry(
                    rawText: rawText,
                    processedText: processedText,
                    modeName: settings.selectedMode.name,
                    duration: recordingDuration,
                    engineUsed: settings.engineType.rawValue,
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
                resumeBackgroundJobs()

            } catch {
                lastError = error.localizedDescription
                state = .idle
                processingStage = .none
                showOverlayWindow = true // Keep open to show error
                recorder.cleanup()
                resumeBackgroundJobs()
            }
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

    // MARK: - File Transcription

    func transcribeSelectedFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .video, .movie, .quickTimeMovie, .mpeg4Movie]
        panel.title = "Select Audio or Video File"
        panel.prompt = "Transcribe"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await processFileTranscription(url: url)
            }
        }
    }

    private func processFileTranscription(url: URL) async {
        let jobID = UUID()
        let fileName = url.lastPathComponent
        let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
        
        let initialJob = BackgroundJob(id: jobID, name: fileName, progress: 0, isPaused: false, engine: engine)
        backgroundJobs.append(initialJob)
        
        lastError = nil

        do {
            let result = try await engine.transcribe(audioURL: url, language: settings.language == "auto" ? nil : settings.language) { progress in
                Task { @MainActor in
                    if let index = self.backgroundJobs.firstIndex(where: { $0.id == jobID }) {
                        self.backgroundJobs[index].progress = progress
                    }
                }
            }
            
            // Success
            backgroundJobs.removeAll { $0.id == jobID }
            lastTranscription = result
            let entry = TranscriptionHistoryEntry(
                rawText: result,
                processedText: result,
                modeName: "File Import",
                duration: 0,
                engineUsed: settings.engineType.rawValue
            )
            Storage.shared.addTranscriptionHistoryEntry(entry)
            history.insert(entry, at: 0)
            
            // Save to desktop by default
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let outputName = url.deletingPathExtension().lastPathComponent + "_transcription.txt"
            let outputURL = desktop.appendingPathComponent(outputName)
            try result.write(to: outputURL, atomically: true, encoding: .utf8)
            
            // Notify user of success
            await MainActor.run {
                lastError = "Success! Transcription of \(fileName) saved to Desktop."
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.lastError?.contains("Success") == true {
                        self.clearError()
                    }
                }
            }
        } catch {
            backgroundJobs.removeAll { $0.id == jobID }
            lastError = "File transcription failed: \(error.localizedDescription)"
        }
    }
}
