import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var result: String?
    @State private var progress: Float = 0
    @State private var isProcessing = false
    @State private var currentFileName: String?
    @State private var error: String?
    @State private var remainingTime: TimeInterval?
    
    // Queue System
    @State private var fileQueue: [URL] = []
    @State private var engine: (any TranscriptionEngine)?

    private var timeRemainingString: String? {
        guard let remaining = remainingTime else { return nil }
        if remaining < 1 {
            return "Finishing..."
        } else if remaining < 60 {
            return "About \(Int(remaining)) seconds remaining"
        } else {
            let minutes = Int(remaining / 60)
            let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
            return "About \(minutes)m \(seconds)s remaining"
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                Divider()
                configBar
                Divider()
                
                if isProcessing {
                    progressView
                } else if result != nil {
                    resultView
                } else {
                    dropZoneView
                }
                
                Spacer(minLength: 0)
            }
            
            errorOverlay
        }
        .frame(minWidth: 400, minHeight: 320)
        .onDisappear {
            engine?.cancel()
            isProcessing = false
            fileQueue.removeAll()
            remainingTime = nil
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .video, .movie, .quickTimeMovie, .mpeg4Movie, .wav, .mp3, .aiff],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addToQueue(urls)
            case .failure(let err):
                self.error = err.localizedDescription
            }
        }
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("File Transcription")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            
            if !fileQueue.isEmpty {
                Text("\(fileQueue.count) in queue")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var configBar: some View {
        HStack(spacing: 12) {
            // Mode Selection
            Menu {
                ForEach(appState.settings.allModes) { mode in
                    Button {
                        appState.settings.selectedModeName = mode.name
                    } label: {
                        Label(mode.name, systemImage: mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    let mode = appState.settings.selectedMode
                    Image(systemName: mode.icon)
                    Text(mode.name)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Language Selection
            Menu {
                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                    Button {
                        appState.settings.language = lang.code
                    } label: {
                        Text(lang.name)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    let currentLang = AppSettings.supportedLanguages.first { $0.code == appState.settings.language }?.name ?? "Auto"
                    Text(currentLang)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            if appState.settings.engineType == .cloud {
                Toggle(isOn: $appState.settings.enableSpeakerDiarization) {
                    Text("Diarization")
                        .font(.system(size: 10, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 4)
            }

            Spacer()
            
            // Engine Selector
            Menu {
                Button {
                    appState.settings.engineType = .local
                } label: {
                    Label("Local (whisper.cpp)", systemImage: "cpu")
                }
                
                Button {
                    appState.settings.engineType = .cloud
                } label: {
                    Label("Cloud (OpenAI)", systemImage: "cloud.fill")
                }
                .disabled(appState.settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.settings.engineType == .cloud ? "cloud.fill" : "cpu")
                    Text(appState.settings.engineType == .cloud ? "Cloud" : "Local")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }

    private var progressView: some View {
        VStack(spacing: 24) {
            Color.clear.frame(height: 20) // Top gap


            
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                
                HStack {
                    if progress < 0.1 {
                        Text("Extracting audio...")
                    } else if progress < 0.2 {
                        Text("Initializing engine...")
                    } else if progress < 0.99 {
                        Text("Transcribing...")
                    } else {
                        Text("Finalizing...")
                    }
                    Spacer()
                    if let timeStr = timeRemainingString {
                        Text(timeStr)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 240)
            }
            
            VStack(spacing: 4) {
                Text(currentFileName ?? "Processing...")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            
            
            // Removed Spacer() to eliminate holes
            
            Button {
                engine?.cancel()
                isProcessing = false
                fileQueue.removeAll()
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancel Transcription")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var resultView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Transcription Complete")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    self.result = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView {
                if let result = result {
                    Text(result)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 180)
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack(spacing: 12) {
                Button {
                    if let result = result {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("Copy Result")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button {
                    self.result = nil
                    if !fileQueue.isEmpty {
                        processNextInQueue()
                    }
                } label: {
                    Text(fileQueue.isEmpty ? "New File" : "Next File (\(fileQueue.count))")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(20)
        .padding(.bottom, 4)
    }

    private var dropZoneView: some View {
        VStack(spacing: 12) {
            // Removed Spacer() to eliminate holes
            
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isDragging ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.02))
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isDragging ? Color.accentColor : .secondary.opacity(0.6))
                        .padding(.bottom, 2)
                    
                    Text("Drop audio or video here")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                    
                    Text("MP3, WAV, M4A, MP4, MOV")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .frame(height: 160)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
            }
            
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to Queue...")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            // Removed Spacer() to eliminate holes
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var errorOverlay: some View {
        Group {
            if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                    Button { self.error = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Drop handling
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                DispatchQueue.main.async {
                    addToQueue([url])
                }
            }
        }
        return true
    }
    
    // MARK: - Queue Logic
    
    private func addToQueue(_ urls: [URL]) {
        fileQueue.append(contentsOf: urls)
        if !isProcessing {
            processNextInQueue()
        }
    }
    
    private func processNextInQueue() {
        guard !fileQueue.isEmpty && !isProcessing else { return }
        let url = fileQueue.removeFirst()
        startTranscription(url: url)
    }
    
    // MARK: - Transcription
    
    private func startTranscription(url: URL) {
        isProcessing = true
        progress = 0
        currentFileName = url.lastPathComponent
        error = nil
        result = nil
        
        let engine = TranscriptionEngineFactory.create(for: appState.settings.engineType, settings: appState.settings)
        self.engine = engine
        
        Task {
            do {
                let text = try await engine.transcribe(
                    audioURL: url,
                    language: appState.settings.language == "auto" ? nil : appState.settings.language
                ) { p, rem in
                    Task { @MainActor in
                        self.progress = p
                        self.remainingTime = rem
                    }
                }
                
                await MainActor.run {
                    self.result = text
                    self.isProcessing = false
                    self.progress = 0
                    self.remainingTime = nil
                }
                
                // Diarization if enabled
                var processedText = text
                var usage: UsageLog? = nil
                
                if appState.settings.enableSpeakerDiarization && appState.settings.postProcessingEngine == .openai {
                    do {
                        let processor = PostProcessor(settings: appState.settings)
                        let diarizationResult = try await processor.diarize(text: text)
                        processedText = diarizationResult.text
                        usage = UsageLog(
                            date: Date(),
                            modeName: "File Diarization",
                            engine: "OpenAI",
                            promptTokens: diarizationResult.promptTokens,
                            completionTokens: diarizationResult.completionTokens,
                            totalTokens: diarizationResult.promptTokens + diarizationResult.completionTokens,
                            estimatedCost: UsageLog.estimateCost(prompt: diarizationResult.promptTokens, completion: diarizationResult.completionTokens, engine: .openai)
                        )
                    } catch {
                        print("⚠️ File diarization failed: \(error)")
                    }
                }
                
                await MainActor.run {
                    self.result = processedText
                    
                    // Save to history (excluding from stats)
                    let entry = TranscriptionHistoryEntry(
                        rawText: text,
                        processedText: processedText,
                        modeName: appState.settings.enableSpeakerDiarization ? "Diarization" : "File Import",
                        duration: 0,
                        engineUsed: appState.settings.engineType.rawValue + (appState.settings.enableSpeakerDiarization ? " + AI" : ""),
                        usage: usage,
                        isFromFileImport: true
                    )
                    Storage.shared.addTranscriptionHistoryEntry(entry)
                    appState.history.insert(entry, at: 0)
                }
            } catch {
                await MainActor.run {
                    // Suppress error if manually stopped
                    if isProcessing {
                        self.error = error.localizedDescription
                    }
                    self.isProcessing = false
                    self.progress = 0
                }
            }
        }
    }
}
