import Foundation
@preconcurrency import AVFoundation

/// Local transcription using whisper.cpp CLI binary.
/// Install via: `brew install whisper-cpp`
/// Models are downloaded automatically by ModelManager to ~/Library/Application Support/WhisperFree/Models/
final class LocalWhisper: TranscriptionEngine, @unchecked Sendable {
    private let modelSize: LocalModelSize
    private var currentProcess: Process?

    init(modelSize: LocalModelSize) {
        self.modelSize = modelSize
    }

    func pause() {
        if let pid = currentProcess?.processIdentifier {
            kill(pid, SIGSTOP)
        }
    }

    func resume() {
        if let pid = currentProcess?.processIdentifier {
            kill(pid, SIGCONT)
        }
    }

    func cancel() {
        currentProcess?.terminate()
    }

    func transcribe(audioURL: URL, language: String?, onProgress: ((Float) -> Void)?) async throws -> String {
        let modelPath = await MainActor.run {
            AppState.shared.modelManager.findModelPath(for: self.modelSize)?.path
        }
        
        guard let path = modelPath else {
            throw TranscriptionError.modelNotDownloaded
        }

        let whisperBinary = findWhisperBinary()
        guard let binary = whisperBinary else {
            throw TranscriptionError.transcriptionFailed("whisper-cpp not found.")
        }

        let wavURL = try await convertTo16kHzWav(audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.currentProcess = process
            process.executableURL = URL(fileURLWithPath: binary)

            var args = [
                "--model", path,
                "--file", wavURL.path,
                "--output-txt",
                "--no-timestamps",
                "--threads", "\(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))"
            ]

            if let lang = language, lang != "auto" {
                args += ["--language", lang]
            }

            process.arguments = args

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Watch stderr for progress
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                
                // whisper.cpp progress format: "whisper_print_progress: progress =  20%"
                if output.contains("progress =") {
                    let parts = output.components(separatedBy: "progress =")
                    if let lastPart = parts.last?.trimmingCharacters(in: .whitespaces),
                       let percentStr = lastPart.components(separatedBy: "%").first,
                       let percent = Float(percentStr.trimmingCharacters(in: .whitespaces)) {
                        onProgress?(percent / 100.0)
                    }
                }
            }

            process.terminationHandler = { [weak self] p in
                self?.currentProcess = nil
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                if p.terminationStatus == 0 {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let text = self?.parseWhisperOutput(output) ?? ""
                    continuation.resume(returning: text)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(errorOutput))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Find whisper binary

    private func findWhisperBinary() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/Cellar/whisper-cpp/1.8.3/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
            "/opt/homebrew/bin/main",
            "/usr/local/bin/main"
        ]

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: url.path) && FileManager.default.isExecutableFile(atPath: url.path) {
                return url.path
            }
        }

        // Try `which` as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["whisper-cpp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private func convertTo16kHzWav(_ inputURL: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_input_\(UUID().uuidString).wav")

        let asset = AVURLAsset(url: inputURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw TranscriptionError.transcriptionFailed("Could not load audio track")
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "audioConvertQueue")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = trackOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        if let error = reader.error ?? writer.error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                        break
                    }
                }
            }
        }
        
        await writer.finishWriting()
        return outputURL
    }

    // MARK: - Parse output

    private func parseWhisperOutput(_ raw: String) -> String {
        // whisper-cpp outputs lines like "[00:00:00.000 --> 00:00:05.000]  Hello world"
        // or plain text depending on flags. We use --no-timestamps so it's plain text
        let lines = raw.components(separatedBy: .newlines)
        let textLines = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.hasPrefix("whisper_") && !$0.hasPrefix("main:") }

        return textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
