import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ─── Accessibility Warning ─────────────
            if !AXIsProcessTrusted() {
                Button {
                    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                    let trusted = AXIsProcessTrustedWithOptions(options)
                    if !trusted {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        if !NSWorkspace.shared.open(url) {
                            let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                            NSWorkspace.shared.open(fallback)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Accessibility Not Granted")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Click to open Settings")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            }

            // ─── Header + Record ────────────────
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("WhisperKiller")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                // Record / Stop button inline
                Button {
                    appState.toggleFromMenuBar()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.state == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 10))
                        Text(appState.state == .recording ? "Stop" : "Rec")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(appState.state == .recording ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(appState.state == .recording ? Color.red : Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                // State indicator
                if appState.state == .processing {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ─── AI Mode Pills ──────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(appState.settings.allModes) { mode in
                        let isActive = appState.settings.selectedModeName == mode.name
                        let isEnabled = appState.settings.isModeEnabled(mode)
                        
                        Button {
                            if isEnabled {
                                appState.settings.selectedModeName = mode.name
                                appState.saveSettings()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 10))
                                Text(mode.name)
                                    .font(.system(size: 11, weight: .medium))
                                
                                if !isEnabled {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isActive
                                    ? Color.accentColor.opacity(0.12)
                                    : (isEnabled ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
                            )
                            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : (isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.secondary.opacity(0.4))))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            // ─── Engine + Language ───────────────
            HStack(spacing: 8) {
                // Engine pill toggle
                HStack(spacing: 0) {
                    ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                        let isActive = appState.settings.engineType == type
                        Button {
                            appState.settings.engineType = type
                            appState.saveSettings()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 9))
                                Text(type == .cloud ? "Cloud" : "Local")
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .fixedSize()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                            .foregroundStyle(isActive ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .frame(height: 24)

                Spacer()

                // Language dropdown
                Menu {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Button {
                            appState.settings.language = lang.code
                            appState.saveSettings()
                        } label: {
                            HStack {
                                Text(lang.name)
                                if appState.settings.language == lang.code {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 9))
                        Text(AppSettings.supportedLanguages.first(where: { $0.code == appState.settings.language })?.name ?? "Auto")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .foregroundStyle(.primary.opacity(0.8))
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .frame(height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Hotkey badge
                Text(appState.settings.hotkeyConfig.displayString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .frame(height: 24)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // ─── Background Jobs ────────────────
            if !appState.backgroundJobs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("BACKGROUND JOBS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(appState.backgroundJobs) { job in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(job.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                if job.isPaused {
                                    HStack(spacing: 3) {
                                        Image(systemName: "pause.fill").font(.system(size: 8))
                                        Text("Priority Wait").font(.system(size: 10))
                                    }
                                    .foregroundStyle(.orange)
                                } else {
                                    Text("\(Int(job.progress * 100))%")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.accentColor)
                                }
                            }
                            
                            ProgressView(value: job.progress)
                                .progressViewStyle(.linear)
                                .tint(job.isPaused ? .orange : .accentColor)
                                .scaleEffect(x: 1, y: 0.5, anchor: .center)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // ─── Last Transcription ─────────────
            if let lastText = appState.lastTranscription {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("LAST TRANSCRIPTION")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(lastText)
                        .font(.caption)
                        .lineLimit(4)
                        .foregroundStyle(.primary)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lastText, forType: .string)
                        appState.copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            appState.copiedFeedback = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.copiedFeedback ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(appState.copiedFeedback ? "Copied!" : "Copy to Clipboard")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appState.copiedFeedback ? Color.green : Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: appState.copiedFeedback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // ─── Error ──────────────────────────
            if let error = appState.lastError {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        appState.clearError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .onTapGesture {
                    appState.clearError()
                }
            }

            Divider()

            // ─── Navigation ─────────────────────
            VStack(spacing: 0) {
                menuButton(icon: "gear", title: "Settings") {
                    AppDelegate.shared?.showSettings()
                }
                menuButton(icon: "clock", title: "History") {
                    AppDelegate.shared?.showHistory()
                }
                menuButton(icon: "doc.badge.plus", title: "Transcribe File...") {
                    appState.transcribeSelectedFile()
                }
                menuButton(icon: "wand.and.stars", title: "Setup Wizard") {
                    AppDelegate.shared?.showSetupWizard()
                }
            }

            Divider()

            menuButton(icon: "power", title: "Quit") {
                NSApplication.shared.terminate(nil)
            }

            Divider()

            menuButton(icon: "arrow.clockwise", title: "Check for Updates...") {
                GitHubUpdater.shared.checkForUpdates(manual: true)
            }
        }
        .frame(width: 340)
        .onAppear {
            if !appState.settings.setupCompleted {
                DispatchQueue.main.async {
                    AppDelegate.shared?.showSetupWizard()
                }
            }
        }
    }

    private func menuButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
