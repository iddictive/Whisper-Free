import SwiftUI
import AVFoundation

struct SetupWizardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var selectedEngine: TranscriptionEngineType = .cloud
    @State private var selectedModel: LocalModelSize = .base
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?
    @State private var micGranted = false
    @State private var whisperInstalled = false
    @State private var animateGlow = false

    private let totalSteps = 5

    // MARK: - Colors

    private let accentGold = SW.accent
    private let accentPink = SW.accentBlue
    private let accentMag  = SW.accentIndigo
    private let bgDark = SW.bg
    private let bgCard = SW.card
    private let bgCardHover = Color(white: 1.0, opacity: 0.09)
    private let borderSubtle = Color(white: 1.0, opacity: 0.08)
    private let textPrimary = Color.white
    private let textSecondary = Color(white: 0.55)

    var body: some View {
        ZStack {
            // Background
            bgDark.ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentGold.opacity(0.1), accentPink.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 60,
                        endRadius: 300
                    )
                )
                .scaleEffect(animateGlow ? 1.1 : 0.9)
                .offset(y: -60)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: animateGlow)

            VStack(spacing: 0) {
                // ─── Header ────────────────────────
                header
                    .padding(.top, 32)
                    .padding(.bottom, 16)

                // ─── Progress bar ──────────────────
                progressBar
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)

                // ─── Content ───────────────────────
                ScrollView(showsIndicators: false) {
                    Group {
                        switch currentStep {
                        case 0: welcomeStep
                        case 1: permissionsStep
                        case 2: engineStep
                        case 3: apiKeyStep
                        case 4: readyStep
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 20)
                }

                Spacer(minLength: 0)

                // ─── Bottom bar ────────────────────
                bottomBar
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 580, height: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshStatus()
            apiKey = appState.settings.apiKey
            selectedEngine = appState.settings.engineType
            selectedModel = LocalModelSize.recommended
            animateGlow = true
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if currentStep == 1 || currentStep == 4 {
                refreshStatus()
                // Auto-advance from permissions to engine if both granted
                if currentStep == 1 && appState.isHotkeyTrusted && micGranted {
                    withAnimation(.spring(response: 0.35)) {
                        currentStep = 2
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Header
    // ═══════════════════════════════════════════════

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer ring glow
                Circle()
                    .stroke(LinearGradient(colors: [accentGold, accentPink], startPoint: .top, endPoint: .bottom).opacity(0.3), lineWidth: 2)
                    .frame(width: 68, height: 68)
                    .blur(radius: 4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentGold.opacity(0.2), accentPink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: stepIcon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(accentPink)
            }

            Text(stepTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)

            Text(stepSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 40)
        }
    }

    private var stepIcon: String {
        ["waveform.circle.fill", "lock.shield", "cpu", "key.fill", "checkmark.seal.fill"][currentStep]
    }

    private var stepTitle: String {
        ["Whisper Free", "Permissions", "Engine", "API Key", "Ready"][currentStep]
    }

    private var stepSubtitle: String {
        [
            "AI voice-to-text, built for macOS",
            "Two quick permissions to enable",
            "Cloud or local — your choice",
            "For cloud transcription & AI modes",
            "Everything's set up"
        ][currentStep]
    }

    // ═══════════════════════════════════════════════
    // MARK: – Progress bar
    // ═══════════════════════════════════════════════

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [accentGold, accentPink, accentMag],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)

                // Step dots
                HStack {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? accentPink : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(step == currentStep ? accentPink : .clear)
                                    .frame(width: 12, height: 12)
                                    .opacity(0.3)
                            )
                        if step < totalSteps - 1 { Spacer() }
                    }
                }
            }
        }
        .frame(height: 12)
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 0: Welcome
    // ═══════════════════════════════════════════════

    private var welcomeStep: some View {
        VStack(spacing: 12) {
            featureCard(icon: "mic.fill", color: .red,
                        title: "⌥+Space to record",
                        desc: "Hold, Toggle, or Push-to-Talk — pick your style")
            featureCard(icon: "waveform", color: accentPink,
                        title: "AI transcription",
                        desc: "Cloud (OpenAI) or Local (whisper.cpp with GPU/NPU)")
            featureCard(icon: "sparkles", color: .purple,
                        title: "Smart post-processing",
                        desc: "Dictation · Email · Code · Notes — or create your own")
            featureCard(icon: "keyboard", color: .orange,
                        title: "Auto-paste anywhere",
                        desc: "Result instantly typed into whichever app is focused")
        }
    }

    private func featureCard(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderSubtle, lineWidth: 1)
        )
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 1: Permissions
    // ═══════════════════════════════════════════════

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            permissionCard(
                icon: "hand.raised.fill",
                title: "Accessibility",
                desc: "For the global ⌥+Space hotkey to work anywhere",
                granted: appState.isHotkeyTrusted
            ) {
                appState.requestAccessibilityPermission()
                if !appState.isHotkeyTrusted {
                    // Try to open the most specific privacy pane for accessibility
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    if !NSWorkspace.shared.open(url) {
                        // Fallback if specific URL fails
                        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                        NSWorkspace.shared.open(fallback)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshStatus() }
            }

            permissionCard(
                icon: "mic.fill",
                title: "Microphone",
                desc: "To capture your voice for transcription",
                granted: micGranted
            ) {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { 
                        micGranted = granted 
                        if !granted {
                            // If denied, guide to settings
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Button {
                refreshStatus()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 12))
                .foregroundStyle(accentGold)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if appState.isTranslocated {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("App Translocation Detected")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    Text("To ensure permissions like Accessibility and Microphone work correctly, please move WhisperFree to your Applications folder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        let url = URL(fileURLWithPath: "/Applications")
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("Open Applications Folder")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.2), lineWidth: 1))
                .padding(.top, 8)
            }
        }
    }

    private func permissionCard(icon: String, title: String, desc: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(granted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(textPrimary)
                Text(desc).font(.system(size: 11)).foregroundStyle(textSecondary)
            }

            Spacer()

            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(granted ? Color.green.opacity(0.15) : borderSubtle, lineWidth: 1)
        )
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 2: Engine
    // ═══════════════════════════════════════════════

    private var engineStep: some View {
        VStack(spacing: 14) {
            // Engine picker
            HStack(spacing: 10) {
                enginePill(type: .cloud, icon: "cloud.fill", label: "Cloud")
                enginePill(type: .local, icon: "desktopcomputer", label: "Local")
            }

            // Engine details
            if selectedEngine == .cloud {
                cloudEngineCard
            } else {
                localEngineCard
            }
        }
    }

    private func enginePill(type: TranscriptionEngineType, icon: String, label: String) -> some View {
        let selected = type == selectedEngine
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedEngine = type }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? accentGold.opacity(0.15) : bgCard)
            .foregroundStyle(selected ? accentGold : textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? accentGold.opacity(0.4) : borderSubtle, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var cloudEngineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.system(size: 11))
                Text("Fast · Accurate · 100+ languages")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(textSecondary)
            }

            tagRow(items: [
                ("checkmark", "OpenAI Whisper API", .green),
                ("wifi", "Requires internet", .orange),
                ("key", "Requires API key", .orange),
            ])

            Text("Audio is sent to OpenAI for processing. Great for maximum accuracy.")
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
        .padding(16)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))
    }

    private var localEngineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            localEngineStatusRow
            
            Text("MODEL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(textSecondary)

            ForEach(LocalModelSize.allCases, id: \.self) { size in
                modelRow(size)
            }
        }
        .padding(16)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))
    }

    private var localEngineStatusRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green).font(.system(size: 11))
                Text("Private · Offline · Free")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(textSecondary)
            }

            HStack(spacing: 10) {
                Image(systemName: whisperInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(whisperInstalled ? .green : .red)
                Text(whisperInstalled ? "whisper-cpp detected" : "whisper-cpp not found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(whisperInstalled ? .green : .red)
                Spacer()
                if !whisperInstalled {
                    Button {
                        installWhisperCpp()
                    } label: {
                        Text("Install (brew)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentPink.opacity(0.2))
                            .foregroundStyle(accentPink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(whisperInstalled ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func modelRow(_ size: LocalModelSize) -> some View {
        let isCurrent = selectedModel == size
        let downloaded = modelManager.isModelDownloaded(size)
        _ = modelManager.isDownloading(size)
        _ = modelManager.progress(for: size)
        _ = modelManager.error(for: size)
        let isRecommended = size == LocalModelSize.recommended

        return HStack(spacing: 10) {
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isCurrent ? accentPink : textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(size.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    if isRecommended {
                        Text("REC")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accentGold.opacity(0.2))
                            .foregroundStyle(accentGold)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(size.sizeDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(textSecondary)
                    Text(size.speedRating)
                        .font(.system(size: 9))
                }
            }

            Spacer()

            if downloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else if let state = modelManager.activeDownloads[size.rawValue] {
                if state.error != nil {
                    Text("Error").font(.system(size: 10)).foregroundStyle(.red)
                } else if state.isPreparing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Preparing...").font(.system(size: 9)).foregroundStyle(textSecondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        ProgressView(value: state.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                        Button {
                            modelManager.cancelDownload(size)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        modelManager.downloadModel(size)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                            Text("Get")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentGold.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isCurrent ? accentGold.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedModel = size
        }
    }

    private func tagRow(items: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.1) { icon, text, color in
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
                    Text(text).font(.system(size: 11)).foregroundStyle(textSecondary)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 3: API Key
    // ═══════════════════════════════════════════════

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            if selectedEngine == .local {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(accentGold)
                    Text("Optional for local engine. Only needed for AI post-processing modes.")
                        .font(.system(size: 12)).foregroundStyle(textSecondary)
                }
                .padding(14)
                .background(accentGold.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accentGold.opacity(0.15), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)

                HStack(spacing: 8) {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Button {
                        testAPI()
                    } label: {
                        Group {
                            if isTestingAPI {
                                ProgressView().controlSize(.mini).tint(accentGold)
                            } else {
                                Text("Test")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .frame(width: 50)
                        .padding(.vertical, 10)
                        .background(accentGold.opacity(0.15))
                        .foregroundStyle(accentGold)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKey.isEmpty || isTestingAPI)
                }

                if let result = apiTestResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.contains("✓") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(result)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(result.contains("✓") ? .green : .red)
                }

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get API key at platform.openai.com")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(accentGold)
                }
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))

            if selectedEngine == .cloud && apiKey.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Cloud engine requires an API key")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 4: Ready
    // ═══════════════════════════════════════════════

    private var readyStep: some View {
        VStack(spacing: 18) {
            // Checklist
            VStack(spacing: 8) {
                readyRow("Accessibility", ok: appState.isHotkeyTrusted)
                readyRow("Microphone", ok: micGranted)
                readyRow("Engine: \(selectedEngine.rawValue)", ok: true)
                if selectedEngine == .cloud {
                    readyRow("API Key", ok: !apiKey.isEmpty)
                } else {
                    readyRow("whisper-cpp", ok: whisperInstalled)
                    readyRow("Model: \(selectedModel.rawValue)", ok: modelManager.isModelDownloaded(selectedModel))
                }
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))

            // Shortcuts
            VStack(spacing: 10) {
                Text("SHORTCUTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(textSecondary)
                HStack(spacing: 24) {
                    shortcutBadge(key: "⌥ Space", label: "Record")
                    shortcutBadge(key: "Esc", label: "Cancel")
                }
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("You can change everything later in Settings")
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
    }

    private func readyRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(ok ? .green : .orange)
            Text(label).font(.system(size: 13)).foregroundStyle(textPrimary)
            Spacer()
            Text(ok ? "Ready" : "Skipped")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? .green : .orange)
        }
    }

    private func shortcutBadge(key: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(key)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundStyle(textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Bottom bar
    // ═══════════════════════════════════════════════

    private var bottomBar: some View {
        HStack {
            // Back
            if currentStep > 0 {
                Button {
                    withAnimation(.spring(response: 0.35)) { currentStep -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("Back").font(.system(size: 13))
                    }
                    .foregroundStyle(textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Step counter
            Text("\(currentStep + 1)/\(totalSteps)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textSecondary)

            Spacer()

            // Next / Finish
            if currentStep < totalSteps - 1 {
                Button {
                    refreshStatus() // Refresh status before moving
                    withAnimation(.spring(response: 0.35)) { currentStep += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentStep == 0 ? "Get Started" : "Next")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [accentGold, accentPink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    finishSetup()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        Text("Launch")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Actions
    // ═══════════════════════════════════════════════

    private func refreshStatus() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        whisperInstalled = checkWhisperInstalled()
        modelManager.refreshDownloadedModels()
    }

    private func checkWhisperInstalled() -> Bool {
        let possibleBins = [
            "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp", "/usr/local/bin/whisper-cpp",
            "/opt/homebrew/bin/main", "/usr/local/bin/main"
        ]
        return possibleBins.contains { path in
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return FileManager.default.fileExists(atPath: url.path) && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private func installWhisperCpp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "/opt/homebrew/bin/brew install whisper-cpp 2>&1 || /usr/local/bin/brew install whisper-cpp 2>&1"]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { refreshStatus() }
    }

    private func testAPI() {
        isTestingAPI = true
        apiTestResult = nil
        Task {
            let url = URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                apiTestResult = (response as? HTTPURLResponse)?.statusCode == 200
                    ? "✓ Valid" : "✗ Invalid key"
            } catch {
                apiTestResult = "✗ Connection failed"
            }
            isTestingAPI = false
        }
    }

    private func finishSetup() {
        appState.settings.apiKey = apiKey
        appState.settings.engineType = selectedEngine
        appState.settings.localModelSize = selectedModel
        appState.settings.setupCompleted = true
        appState.saveSettings()
        appState.reloadHotkeyManager()
        onComplete()
    }
}
