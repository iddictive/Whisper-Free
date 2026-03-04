import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ─── Header + Record ────────────────
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Whisper Free")
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
                        Button {
                            appState.settings.selectedModeName = mode.name
                            appState.saveSettings()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 10))
                                Text(mode.name)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isActive
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.primary.opacity(0.04)
                            )
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
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
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
                menuButton(icon: "wand.and.stars", title: "Setup Wizard") {
                    AppDelegate.shared?.showSetupWizard()
                }
            }

            Divider()

            menuButton(icon: "power", title: "Quit") {
                NSApplication.shared.terminate(nil)
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
