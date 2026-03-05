import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private var modelManager: ModelManager { appState.modelManager }
    @ObservedObject private var updater = GitHubUpdater.shared
    @State private var selectedTab = "general"
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?
    @State private var transcriptionTab = 0
    @State private var newModeName = ""
    @State private var newModeDescription = ""
    @State private var newModeExampleInput = ""
    @State private var newModeExampleOutput = ""
    @State private var newModePrompt = ""
    @State private var newModeIcon = "sparkles"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("App", systemImage: "apps.iphone")
                    .tag("app")
                Label("Capture & Automation", systemImage: "mic.fill")
                    .tag("capture")
                Label("Engine & API", systemImage: "cpu.fill")
                    .tag("engine")
                Label("AI Modes", systemImage: "sparkles")
                    .tag("modes")
                Label("Usage & About", systemImage: "info.circle.fill")
                    .tag("info")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Form {
                if !appState.isHotkeyTrusted && selectedTab != "info" {
                    permissionBanner
                }
                
                switch selectedTab {
                case "app": appSection
                case "capture": captureSection
                case "engine": engineSection
                case "modes": modesSection
                case "info": infoSection
                default: Text("Select a category")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            modelManager.refreshDownloadedModels()
        }
    }

    private var permissionBanner: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Required")
                        .font(.headline)
                    Text("Global hotkeys won't work without this permission.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Grant Access…") {
                    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sections

    private var appSection: some View {
        Group {
            Section("Preferences") {
                Picker("Preferred Language", selection: $appState.settings.language) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appState.settings.language) { _, _ in
                    appState.saveSettings()
                }
                
                Toggle("Monochrome menu bar icon", isOn: $appState.settings.useMonochromeMenuIcon)
                    .onChange(of: appState.settings.useMonochromeMenuIcon) { _, _ in
                        appState.saveSettings()
                    }
            }
            
            Section("Software Updates") {
                Toggle("Automatically check for updates", isOn: $appState.settings.automaticallyChecksForUpdates)
                    
                Toggle("Automatically download updates", isOn: $appState.settings.automaticallyDownloadsUpdates)
                    .disabled(!appState.settings.automaticallyChecksForUpdates)
                
                if let error = updater.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                if updater.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: updater.downloadProgress)
                            .progressViewStyle(.linear)
                        Text("Downloading update... \(Int(updater.downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if updater.updateAvailable {
                    Button("Download & Install (v\(updater.latestVersion ?? ""))") {
                        updater.startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(updater.isChecking ? "Checking..." : "Check for Updates Now...") {
                        updater.checkForUpdates(manual: true)
                    }
                    .disabled(updater.isChecking)
                    .padding(.top, 4)
                    .font(.caption)
                }
            }
        }
    }

    private var captureSection: some View {
        Group {
            Section("Recording Mode") {
                Picker("Capture Style", selection: $appState.settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .onChange(of: appState.settings.recordingMode) { _, _ in
                    appState.saveSettings()
                }
                
                Text(appState.settings.recordingMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Shortcut") {
                HotkeyRecorderView(config: $appState.settings.hotkeyConfig)
                    .padding(.vertical, 4)
                    .onChange(of: appState.settings.hotkeyConfig) { _, _ in
                        appState.saveSettings()
                        appState.reloadHotkeyManager()
                    }
            }
            
            Section("Automation") {
                Toggle("Auto-type into active app", isOn: $appState.settings.autoTypeResult)
                    .onChange(of: appState.settings.autoTypeResult) { _, _ in
                        appState.saveSettings()
                    }
                
                Toggle("Auto-Enter (send message automatically)", isOn: $appState.settings.experimentalAutoEnter)
                    .onChange(of: appState.settings.experimentalAutoEnter) { _, _ in
                        appState.saveSettings()
                    }
                
                Text("Auto-Enter simulates a Return key press after text insertion. Useful for chat applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Interface") {
                Toggle("Show floating recording pill", isOn: $appState.settings.showOverlay)
                    .onChange(of: appState.settings.showOverlay) { _, _ in
                        appState.saveSettings()
                    }
            }
        }
    }

    private var engineSection: some View {
        Group {
            Section("Transcription Engine") {
                Picker("Model Source", selection: $appState.settings.engineType) {
                    ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .frame(width: 20)
                            Text(type.rawValue)
                        }.tag(type)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.engineType) { _, newValue in
                    if newValue == .local && appState.settings.selectedModeName == TranscriptionMode.dictation.name {
                        appState.settings.selectedModeName = TranscriptionMode.notes.name
                    }
                    appState.saveSettings()
                }
            }

            if appState.settings.engineType == .local {
                Section("Local Models (whisper.cpp)") {
                    ForEach(LocalModelSize.allCases, id: \.self) { size in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(size.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                Text(size.sizeDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if modelManager.isModelDownloaded(size) {
                                if appState.settings.localModelSize == size {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Use") {
                                        appState.settings.localModelSize = size
                                        appState.saveSettings()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                Button(role: .destructive) {
                                    modelManager.deleteModel(size)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else if let state = modelManager.activeDownloads[size.rawValue] {
                                if state.error != nil {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Error").font(.caption2).foregroundStyle(.red)
                                        Button("Retry") {
                                            modelManager.downloadModel(size)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption2)
                                        .foregroundStyle(SW.accent)
                                    }
                                } else if state.isPreparing {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.mini)
                                        Text("Preparing...").font(.caption2).foregroundStyle(.secondary)
                                    }
                                } else {
                                    ProgressView(value: state.progress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 80)
                                }
                            } else {
                                Button("Download") {
                                    modelManager.downloadModel(size)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("AI Refinement & API Keys") {
                AIConfigView(settings: $appState.settings, onSave: { appState.saveSettings() })
            }
        }
    }

    private var modesSection: some View {
        Group {
            Text("Select Active Mode")
                .font(.headline)
                .padding(.top, 8)
                .padding(.leading, 16)

            ForEach(appState.settings.allModes) { mode in
                // Disable dictation if local engine is enabled (User Request)
                let isDictation = mode.name == TranscriptionMode.dictation.name
                let isDisabledByEngine = isDictation && appState.settings.engineType == .local
                let isLocked = !appState.settings.isModeEnabled(mode)
                
                if !isDisabledByEngine {
                    Section {
                        ModeCard(
                            mode: mode,
                            isSelected: appState.settings.selectedModeName == mode.name,
                            isEnabled: !isLocked,
                            onSelect: {
                                if !isLocked {
                                    appState.settings.selectedModeName = mode.name
                                    appState.saveSettings()
                                }
                            },
                            onDelete: mode.isBuiltIn ? nil : {
                                appState.settings.customModes.removeAll { $0.id == mode.id }
                                if appState.settings.selectedModeName == mode.name {
                                    appState.settings.selectedModeName = TranscriptionMode.dictation.name
                                }
                                appState.saveSettings()
                            }
                        )
                    }
                }
            }
            
            Section("Create Custom Mode") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mode Name").font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderName, text: $newModeName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description").font(.caption).foregroundStyle(.secondary)
                        TextField(TranscriptionMode.placeholderDescription, text: $newModeDescription)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Input").font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleInput, placeholder: TranscriptionMode.placeholderExampleInput)
                                .frame(height: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example Output").font(.caption).foregroundStyle(.secondary)
                            TextEditorCustom(text: $newModeExampleOutput, placeholder: TranscriptionMode.placeholderExampleOutput)
                                .frame(height: 60)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt (Instructions for AI)").font(.caption).foregroundStyle(.secondary)
                        TextEditorCustom(text: $newModePrompt, placeholder: TranscriptionMode.placeholderPrompt, isMonospaced: true)
                            .frame(minHeight: 100)
                    }
                    
                    Button {
                        let mode = TranscriptionMode(
                            name: newModeName,
                            icon: newModeIcon,
                            description: newModeDescription,
                            exampleInput: newModeExampleInput,
                            exampleOutput: newModeExampleOutput,
                            systemPrompt: newModePrompt,
                            isBuiltIn: false
                        )
                        appState.settings.customModes.append(mode)
                        appState.saveSettings()
                        newModeName = ""
                        newModeDescription = ""
                        newModeExampleInput = ""
                        newModeExampleOutput = ""
                        newModePrompt = ""
                    } label: {
                        Label("Add Mode", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(newModeName.isEmpty || newModePrompt.isEmpty)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var infoSection: some View {
        Group {
            Section("Usage Statistics (7 Days)") {
                let logs = appState.settings.usageLogs
                let totalTokens = logs.reduce(0) { $0 + $1.totalTokens }
                let totalCost = logs.reduce(0.0) { $0 + $1.estimatedCost }
                
                HStack(spacing: 40) {
                    VStack(alignment: .leading) {
                        Text("Total Tokens").font(.caption).foregroundStyle(.secondary)
                        Text("\(totalTokens)").font(.title2).bold().foregroundStyle(SW.accent)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Est. Cost").font(.caption).foregroundStyle(.secondary)
                        Text("$\(String(format: "%.4f", totalCost))").font(.title2).bold().foregroundStyle(.green)
                    }
                    
                    Spacer()
                    
                    Button("Reset Logs") {
                        appState.settings.usageLogs.removeAll()
                        appState.saveSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
                
                if !logs.isEmpty {
                    DisclosureGroup("Recent Activity Details") {
                        VStack {
                            ForEach(logs.reversed()) { log in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(log.modeName).font(.system(size: 12, weight: .bold))
                                        Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("\(log.totalTokens) tokens").font(.system(size: 11, design: .monospaced))
                                        Text(log.engine).font(.system(size: 9)).foregroundStyle(.secondary).italic()
                                    }
                                }
                                .padding(.vertical, 2)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            Section("About Whisper Free") {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.1))
                        Image(systemName: "microphone.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [SW.accent, SW.accentBlue], startPoint: .top, endPoint: .bottom))
                    }
                    .frame(width: 80, height: 80)
                    
                    VStack(spacing: 8) {
                        Text("Whisper Free").font(.system(size: 28, weight: .bold))
                        Text("Version 2.0").font(.subheadline).foregroundStyle(.secondary)
                    }
                    
                    Text("Hyper-fast voice to text for macOS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 24) {
                        Link("GitHub", destination: URL(string: "https://github.com/iddictive/Whisper-Free")!)
                        Link("iddictive", destination: URL(string: "https://github.com/iddictive")!)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - API Test

    private func testAPIKey() {
        isTestingAPI = true
        apiTestResult = nil

        Task {
            let url = URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(appState.settings.apiKey)", forHTTPHeaderField: "Authorization")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    apiTestResult = "✓ API key is valid"
                } else {
                    apiTestResult = "✗ Invalid API key"
                }
            } catch {
                apiTestResult = "✗ Connection error: \(error.localizedDescription)"
            }
            isTestingAPI = false
        }
    }
}

// MARK: - Helper Views

struct AIConfigView: View {
    @Binding var settings: AppSettings
    var onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Toggle("Enable AI Refinement Globally", isOn: $settings.enablePostProcessing)
                .onChange(of: settings.enablePostProcessing) { _, _ in
                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                    onSave()
                }
            
            Picker("AI Engine", selection: $settings.postProcessingEngine) {
                ForEach(PostProcessingEngine.allCases, id: \.self) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.enablePostProcessing)
            .onChange(of: settings.postProcessingEngine) { _, _ in
                settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                onSave()
            }
            
            let requiresOpenAI = settings.engineType == .cloud || (settings.enablePostProcessing && settings.postProcessingEngine == .openai)
            let requiresPerplexity = settings.enablePostProcessing && settings.postProcessingEngine == .perplexity
            
            if requiresOpenAI || requiresPerplexity {
                VStack(alignment: .leading, spacing: 12) {
                    if requiresOpenAI {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("OpenAI API Key").font(.caption).foregroundStyle(.secondary)
                                if settings.engineType == .cloud {
                                    Text("(Required for Transcription)").font(.system(size: 9)).foregroundStyle(.orange)
                                }
                            }
                            SecureField("sk-...", text: $settings.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.apiKey) { _, _ in
                                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                    onSave()
                                }
                        }
                    }
                    
                    if requiresPerplexity {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Perplexity API Key").font(.caption).foregroundStyle(.secondary)
                            SecureField("pplx-...", text: $settings.perplexityApiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.perplexityApiKey) { _, _ in
                                    settings.selectedModeName = settings.validatedModeName(currentName: settings.selectedModeName)
                                    onSave()
                                }
                        }
                    }
                    
                    if settings.enablePostProcessing {
                        Text(settings.postProcessingEngine == .perplexity 
                             ? "Perplexity Sonar: Best for intelligent grammar/flow." 
                             : "OpenAI GPT: Reliable formatting and structuring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ModeCard: View {
    let mode: TranscriptionMode
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(mode.name, systemImage: mode.icon)
                            .font(.headline)
                            .foregroundStyle(isSelected ? SW.accent : (isEnabled ? .primary : .secondary))
                        
                        if !isEnabled {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if !isEnabled {
                        Text("Requires API Key & AI Refinement Enabled")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange.opacity(0.8))
                            .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { isSelected },
                        set: { if $0 && isEnabled { onSelect() } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!isEnabled)
                    
                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .opacity(isEnabled ? 1.0 : 0.6)
            
            VStack(alignment: .leading, spacing: 10) {
                ExampleBox(title: "Input:", text: mode.exampleInput, icon: "mic")
                ExampleBox(title: "Output:", text: mode.exampleOutput, icon: "sparkles", isOutput: true)
            }
            .opacity(isEnabled || mode.name == TranscriptionMode.dictation.name ? 1.0 : 0.4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled { onSelect() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct ExampleBox: View {
    let title: String
    let text: String
    let icon: String
    var isOutput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isOutput ? SW.accentBlue : SW.text3)
            
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOutput ? SW.accentBlue.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
                )
                .cornerRadius(6)
                .foregroundStyle(.primary)
        }
    }
}

struct TextEditorCustom: View {
    @Binding var text: String
    let placeholder: String
    var isMonospaced: Bool = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            
            TextEditor(text: $text)
                .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
