import SwiftUI
import UniformTypeIdentifiers
import CoreMedia

// MARK: - Queue Item Model

enum QueueItemStatus: Equatable {
    case queued
    case extracting
    case uploading
    case transcribing
    case postProcessing
    case done
    case error(String)
    case cancelled

    var label: String {
        switch self {
        case .queued: return "In Queue"
        case .extracting: return "Converting..."
        case .uploading: return "Uploading..."
        case .transcribing: return "Transcribing..."
        case .postProcessing: return "AI Processing..."
        case .done: return "Done"
        case .error: return "Error"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .queued: return "clock"
        case .extracting: return "waveform"
        case .uploading: return "arrow.up.circle"
        case .transcribing: return "text.bubble"
        case .postProcessing: return "sparkles"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .queued: return .secondary
        case .extracting, .uploading, .transcribing, .postProcessing: return .accentColor
        case .done: return .accentColor // Changed from green to blue
        case .error: return .red
        case .cancelled: return .orange
        }
    }
}

@MainActor
final class QueueItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String

    @Published var status: QueueItemStatus = .queued
    @Published var progress: Float = 0
    @Published var result: String?
    @Published var rawResult: String?
    @Published var summary: String?
    @Published var estimatedCost: Double?
    @Published var rangeStart: Double = 0
    @Published var rangeEnd: Double = 0
    @Published var durationSeconds: TimeInterval?
    // Fix RangeSlider window dragging (High-priority gesture) (completed)
    // Fix RangeSlider clipping (Horizontal padding) (completed)
    // Hide cost display completely for Local mode (completed)
    // Replace hardcoded durations with dynamic file timestamps (completed)
    @Published var transcriptionSpeed: Double? // e.g., 12x realtime
    @Published var isExpanded = false
    @Published var isSummarizing = false
    @Published var summaryError: String?

    var historyEntryID: UUID?

    var selectedDuration: TimeInterval {
        guard let total = durationSeconds else { return 0 }
        let end = rangeEnd > 0 ? rangeEnd : total
        return max(0, end - rangeStart)
    }

    var engine: (any TranscriptionEngine)?
    private var transcriptionTask: Task<Void, Never>?
    private var startTime: Date?

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
    }

    func loadDuration() async {
        if let dur = await CloudWhisper.fileDuration(url: url) {
            self.durationSeconds = dur
            self.rangeEnd = dur
            self.estimatedCost = UsageLog.estimateAudioCost(durationSeconds: dur)
        }
    }

    func updateCost() {
        self.estimatedCost = UsageLog.estimateAudioCost(durationSeconds: selectedDuration)
    }

    func cancel() {
        engine?.cancel()
        transcriptionTask?.cancel()
        status = .cancelled
        progress = 0
    }

    func startTranscription(settings: AppSettings, appState: AppState) {
        startTime = Date()
        let engine = TranscriptionEngineFactory.create(for: settings.engineType, settings: settings)
        self.engine = engine

        transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                self.status = .extracting

                let timeRange: CMTimeRange? = (rangeStart > 0 || (rangeEnd > 0 && rangeEnd < (self.durationSeconds ?? 0))) ? CMTimeRange(
                    start: CMTime(seconds: rangeStart, preferredTimescale: 1000),
                    duration: CMTime(seconds: max(0, rangeEnd - rangeStart), preferredTimescale: 1000)
                ) : nil

                let text = try await engine.transcribe(
                    audioURL: self.url,
                    language: settings.language == "auto" ? nil : settings.language,
                    timeRange: timeRange
                ) { p, _ in
                    Task { @MainActor in
                        self.progress = p
                        let isLocal = settings.engineType == .local
                        
                        if p < (isLocal ? 0.15 : 0.10) {
                            self.status = .extracting
                        } else if !isLocal && p < 0.30 {
                            self.status = .uploading
                        } else {
                            self.status = .transcribing
                        }
                    }
                }

                // AI Refinement post-processing
                // If Diarization is enabled, we skip standard refinement to avoid double-processing/hallucinations
                var processedText = text
                var totalPromptTokens = 0
                var totalCompletionTokens = 0
                var usage: UsageLog? = nil
                let shouldRunDiarization = settings.enableSpeakerDiarization && settings.canUseSpeakerDiarization
                let shouldRunStandardPostProcessing = !shouldRunDiarization
                    && settings.enablePostProcessing
                    && settings.selectedMode.name != "Raw"
                    && !settings.selectedMode.systemPrompt.isEmpty

                if shouldRunDiarization {
                    print("ℹ️ Skipping standard AI refinement because Diarization is active.")
                } else if shouldRunStandardPostProcessing {
                    await MainActor.run { self.status = .postProcessing }
                    do {
                        let processor = PostProcessor(settings: settings)
                        let result = try await processor.process(text: text, mode: settings.selectedMode)
                        processedText = result.text
                        totalPromptTokens += result.promptTokens
                        totalCompletionTokens += result.completionTokens
                    } catch {
                        print("⚠️ File AI refinement failed: \(error)")
                    }
                }

                // Diarization post-processing
                if shouldRunDiarization {
                    await MainActor.run { self.status = .postProcessing }
                    do {
                        let processor = PostProcessor(settings: settings)
                        let diarizationResult = try await processor.diarize(text: processedText)
                        processedText = diarizationResult.text
                        totalPromptTokens += diarizationResult.promptTokens
                        totalCompletionTokens += diarizationResult.completionTokens
                    } catch {
                        print("⚠️ File diarization failed: \(error)")
                    }
                }
                
                // Create final usage log if tokens were consumed
                if totalPromptTokens + totalCompletionTokens > 0 {
                    let usageEngine: PostProcessingEngine = shouldRunDiarization ? .openai : settings.postProcessingEngine
                    usage = UsageLog(
                        date: Date(),
                        modeName: shouldRunDiarization ? "Diarization" : settings.selectedMode.name,
                        engine: usageEngine.rawValue,
                        promptTokens: totalPromptTokens,
                        completionTokens: totalCompletionTokens,
                        totalTokens: totalPromptTokens + totalCompletionTokens,
                        estimatedCost: UsageLog.estimateCost(prompt: totalPromptTokens, completion: totalCompletionTokens, engine: usageEngine)
                    )
                }

                await MainActor.run {
                    self.rawResult = text
                    self.result = processedText
                    self.summary = nil
                    self.summaryError = nil
                    self.status = .done
                    self.progress = 1.0
                    self.isExpanded = true

                    // Calculate speed
                    if let dur = self.durationSeconds, let start = self.startTime {
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed > 0 {
                            self.transcriptionSpeed = dur / elapsed
                        }
                    }

                    // Save to history
                    let entry = TranscriptionHistoryEntry(
                        rawText: text,
                        processedText: processedText,
                        modeName: settings.selectedMode.name,
                        duration: 0,
                        engineUsed: settings.engineType.rawValue + (totalPromptTokens + totalCompletionTokens > 0 ? " + AI" : ""),
                        usage: usage,
                        isFromFileImport: true
                    )
                    self.historyEntryID = entry.entryId
                    Storage.shared.addTranscriptionHistoryEntry(entry)
                    appState.history.insert(entry, at: 0)
                }
            } catch {
                await MainActor.run {
                    if self.status != .cancelled {
                        self.status = .error(error.localizedDescription)
                    }
                    self.progress = 0
                }
            }
        }
    }

    func summarize(appState: AppState) {
        guard !isSummarizing else { return }

        let sourceText = (rawResult ?? result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            summaryError = "Nothing to summarize yet."
            return
        }

        isSummarizing = true
        summaryError = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let processor = PostProcessor(settings: appState.settings)
                let summaryResult = try await processor.summarizeTranscript(text: sourceText)
                let totalTokens = summaryResult.promptTokens + summaryResult.completionTokens
                let usage = totalTokens > 0 ? UsageLog(
                    date: Date(),
                    modeName: "Auto Summary",
                    engine: summaryResult.engine.rawValue,
                    promptTokens: summaryResult.promptTokens,
                    completionTokens: summaryResult.completionTokens,
                    totalTokens: totalTokens,
                    estimatedCost: UsageLog.estimateCost(
                        prompt: summaryResult.promptTokens,
                        completion: summaryResult.completionTokens,
                        engine: summaryResult.engine
                    )
                ) : nil

                await MainActor.run {
                    self.summary = summaryResult.text
                    self.isSummarizing = false

                    if let historyEntryID = self.historyEntryID {
                        appState.saveSummary(entryId: historyEntryID, summary: summaryResult.text, usage: usage)
                    }
                }
            } catch {
                await MainActor.run {
                    self.summaryError = error.localizedDescription
                    self.isSummarizing = false
                }
            }
        }
    }
}

// MARK: - Main View

struct FileTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false
    @State private var showFilePicker = false
    @State private var error: String?

    @State private var queueItems: [QueueItem] = []
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                configBar
                Divider()

                if queueItems.isEmpty {
                    dropZoneView
                        .padding(.top, 20)
                } else {
                    queueListView
                }

                Spacer(minLength: 0)

                if !queueItems.isEmpty {
                    bottomBar
                }
            }

            errorOverlay
        }
        .frame(minWidth: 400, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("File Transcription")
                    .font(.system(size: 13, weight: .semibold))
            }
            
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if !queueItems.isEmpty {
                        let totalCost = queueItems.compactMap { $0.estimatedCost }.reduce(0, +)
                        let doneCount = queueItems.filter { $0.status == .done }.count
                        
                        if appState.settings.engineType == .cloud && totalCost > 0 {
                            Text("Est. Cost: $\(String(format: "%.3f", totalCost))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        Text("\(doneCount)/\(queueItems.count) files")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    
                    if !queueItems.isEmpty && !isProcessing {
                        Button(role: .destructive) {
                            for item in queueItems { item.cancel() }
                            queueItems.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.red.opacity(0.8))
                        .help("Clear All Files")
                    }
                }
            }
        }
        .onDisappear {
            for item in queueItems { item.cancel() }
            queueItems.removeAll()
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("File Transcription")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

            if !queueItems.isEmpty {
                let doneCount = queueItems.filter { $0.status == .done }.count
                Text("\(doneCount)/\(queueItems.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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

    // MARK: - Config Bar

    private var configBar: some View {
        HStack(spacing: 12) {
            // Mode Selection
            Menu {
                ForEach(appState.settings.allModes) { mode in
                    let isEnabled = appState.settings.isModeEnabled(mode)
                    Button {
                        appState.settings.selectedModeName = mode.name
                    } label: {
                        HStack {
                            Text(mode.name)
                            if !isEnabled {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                    .disabled(!isEnabled)
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

            if appState.settings.engineType == .cloud || appState.settings.canUseSpeakerDiarization || appState.settings.enableSpeakerDiarization {
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

    // MARK: - Queue List

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(queueItems) { item in
                    QueueCardView(item: item, onCancel: {
                        cancelItem(item)
                    }, onRemove: {
                        removeItem(item)
                    })
                }

                // Drop zone at the bottom of the queue
                addMoreDropZone
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var addMoreDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDragging ? Color.accentColor.opacity(0.05) : Color.clear)
                )

            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Drop more files or click to add")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 40)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
        .onTapGesture {
            showFilePicker = true
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Total estimated cost
                if appState.settings.engineType == .cloud {
                    let totalCost = queueItems.compactMap(\.estimatedCost).reduce(0, +)
                    if totalCost > 0 {
                        Text("Total Estimated Cost: ~$\(String(format: "%.2f", totalCost))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }

                if !queueItems.isEmpty {
                    let queuedCount = queueItems.filter { $0.status == .queued }.count
                    if queuedCount > 0 {
                        Button {
                            startAllQueued()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                Text("Start All (\(queuedCount))")
                            }
                            .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.accentColor)
                    }
                }

                Spacer()

                Button {
                    clearCompleted()
                } label: {
                    Text("Clear Done")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(queueItems.filter { $0.status == .done }.isEmpty)

                Button {
                    showFilePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Files")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Drop Zone (empty state)

    private var dropZoneView: some View {
        VStack(spacing: 12) {
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Error Overlay

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

    // MARK: - Drop Handling

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
        for url in urls {
            let item = QueueItem(url: url)
            queueItems.append(item)

            // Load duration and cost estimate
            Task {
                await item.loadDuration()
            }
        }
        // processNextInQueue() removed to wait for user confirmation
    }

    private func processNextInQueue() {
        // Find the first queued item that hasn't started
        guard let nextItem = queueItems.first(where: { $0.status == .queued }) else {
            isProcessing = false
            return
        }

        isProcessing = true
        nextItem.startTranscription(settings: appState.settings, appState: appState)

        // When this item finishes, process the next one
        Task {
            // Observe the item's status
            while true {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let status = nextItem.status
                if status == .done || status == .cancelled || {
                    if case .error = status { return true }
                    return false
                }() {
                    break
                }
            }
            processNextInQueue()
        }
    }

    private func cancelItem(_ item: QueueItem) {
        item.cancel()
    }

    private func removeItem(_ item: QueueItem) {
        item.cancel()
        queueItems.removeAll { $0.id == item.id }
    }

    private func clearCompleted() {
        queueItems.removeAll { $0.status == .done }
    }

    private func startAllQueued() {
        guard !isProcessing else { return }
        processNextInQueue()
    }
}

// MARK: - Native Window Drag Blocker

/// A container that prevents macOS from dragging the window when clicking/dragging inside it.
/// Necessary when NSWindow.isMovableByWindowBackground is true.
struct NonDraggableContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            NonDraggableRepresentable()
            content
        }
    }
}

private struct NonDraggableRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Range Slider Component

struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let range: ClosedRange<Double>
    let onEditingChanged: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width - 20 // 10px padding on each side for thumbs

            NonDraggableContainer {
                ZStack(alignment: .leading) {
                    // Transparent background to claim the area
                    Color.black.opacity(0.0001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())

                    // Background Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 4)
                        .padding(.horizontal, 10)

                    // Active Track
                    let startX = CGFloat((start - range.lowerBound) / (range.upperBound - range.lowerBound)) * totalWidth
                    let endX = CGFloat((end - range.lowerBound) / (range.upperBound - range.lowerBound)) * totalWidth
                    let trackWidth = max(0, endX - startX)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: trackWidth, height: 4)
                        .offset(x: startX + 10)

                    // Start Thumb
                    ThumbView()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .offset(x: startX - 5)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("sliderTrack"))
                                .onChanged { value in
                                    let delta = Double(value.location.x - 10) / Double(totalWidth)
                                    let newValue = min(max(range.lowerBound, range.lowerBound + delta * (range.upperBound - range.lowerBound)), end - 0.5)
                                    start = newValue
                                    onEditingChanged()
                                }
                        )

                    // End Thumb
                    ThumbView()
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .offset(x: endX - 5)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("sliderTrack"))
                                .onChanged { value in
                                    let delta = Double(value.location.x - 10) / Double(totalWidth)
                                    let newValue = max(min(range.upperBound, range.lowerBound + delta * (range.upperBound - range.lowerBound)), start + 0.5)
                                    end = newValue
                                    onEditingChanged()
                                }
                        )
                }
                .coordinateSpace(name: "sliderTrack")
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
    }

    struct ThumbView: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2, x: 0, y: 1)
                Circle()
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
    }
}

// MARK: - Queue Card View

struct QueueCardView: View {
    @ObservedObject var item: QueueItem
    var onCancel: () -> Void
    var onRemove: () -> Void
    @EnvironmentObject private var appState: AppState

    private var fileExtIcon: String {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return "film"
        case "mp3": return "music.note"
        case "wav", "aiff": return "waveform"
        case "m4a": return "music.quarternote.3"
        default: return "doc"
        }
    }

    private var isError: Bool {
        if case .error = item.status { return true }
        return false
    }

    private var isFinished: Bool {
        item.status == .done || item.status == .cancelled || isError
    }

    private var errorMessage: String? {
        if case .error(let msg) = item.status { return msg }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            
            if item.status == .queued, let duration = item.durationSeconds, duration > 1 {
                trimSection(totalDuration: duration)
            }
            
            progressRow
            metricsRow
            resultRow
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(item.status == .done ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }

    // MARK: - Row 1: Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: fileExtIcon)
                .font(.system(size: 12))
                .foregroundStyle(item.status.color)
                .frame(width: 16)

            Text(item.fileName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            statusBadge
            actionButton
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.status.icon)
                .font(.system(size: 9))
            Text(item.status.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(item.status.color)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isFinished {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Remove from queue")
        } else if item.status == .queued {
            HStack(spacing: 8) {
                Button {
                    item.startTranscription(settings: AppState.shared.settings, appState: AppState.shared)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Start")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        } else {
            Button(action: onCancel) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 22, height: 22)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
            .help("Stop Processing")
        }
    }

    // MARK: - Row 2: Progress

    @ViewBuilder
    private var progressRow: some View {
        if !isFinished && item.status != .queued {
            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(item.status.color)
        }
    }

    // MARK: - Row 3: Metrics

    private var metricsRow: some View {
        HStack(spacing: 12) {
            costLabel
            speedLabel
            errorLabel
            Spacer()
            percentLabel
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        if let dur = item.durationSeconds {
            Text(formatDuration(dur))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var costLabel: some View {
        let settings = AppState.shared.settings
        if settings.engineType == .cloud, let cost = item.estimatedCost {
            Text("$\(String(format: "%.2f", cost))")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var speedLabel: some View {
        if let speed = item.transcriptionSpeed {
            HStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                Text("\(String(format: "%.0f", speed))x realtime")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let msg = errorMessage {
            Text(msg)
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var percentLabel: some View {
        if item.status == .done {
            Text("100%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.blue)
        } else if item.progress > 0 && !isError && item.status != .cancelled {
            Text(String(format: "%d%%", Int(item.progress * 100)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private func trimSection(totalDuration: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label("Trim Segment", systemImage: "scissors")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatDuration(item.rangeStart)) / \(formatDuration(item.rangeEnd))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text("(\(formatDuration(item.selectedDuration)) selected)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            RangeSlider(
                start: $item.rangeStart,
                end: $item.rangeEnd,
                range: 0...totalDuration,
                onEditingChanged: {
                    item.updateCost()
                }
            )
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Row 4: Result

    @ViewBuilder
    private var resultRow: some View {
        if item.status == .done, let result = item.result {
            DisclosureGroup(isExpanded: $item.isExpanded) {
                resultContent(result)
            } label: {
                Text("Show Result")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func resultContent(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    transcriptBlock(title: "Transcript", text: result)

                    if let summary = item.summary, !summary.isEmpty {
                        transcriptBlock(title: "Auto Summary", text: summary)
                    }

                    if let summaryError = item.summaryError, !summaryError.isEmpty {
                        Text(summaryError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    item.summarize(appState: appState)
                } label: {
                    HStack(spacing: 4) {
                        if item.isSummarizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(item.summary == nil ? "Summarize" : "Re-Summarize")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(item.isSummarizing)

                if let summary = item.summary, !summary.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text("Copy Summary")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.top, 4)
    }

    private func transcriptBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
