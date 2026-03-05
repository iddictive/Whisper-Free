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

    func transcribe(audioURL: URL, language: String?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        let startTime = Date()
        
        // Stage 1: Convert/Extract audio (0-10% of total progress)
        // Skip conversion if file is already 16kHz WAV (recorded by AudioRecorder)
        let wavURL: URL
        let shouldCleanupWav: Bool
        
        if isAlready16kHzWav(audioURL) {
            print("whisper_debug: ✅ Audio is already 16kHz WAV, skipping conversion")
            wavURL = audioURL
            shouldCleanupWav = false
        } else {
            print("whisper_debug: 🔄 Converting audio to 16kHz WAV...")
            wavURL = try await convertTo16kHzWav(audioURL) { conversionProgress in
                let totalProgress = conversionProgress * 0.1
                onProgress?(totalProgress, nil)
            }
            shouldCleanupWav = true
        }
        defer { if shouldCleanupWav { try? FileManager.default.removeItem(at: wavURL) } }

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

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            self.currentProcess = process
            process.executableURL = URL(fileURLWithPath: binary)

            var args = [
                "--model", path,
                "--file", wavURL.path,
                "--no-timestamps",
                "--print-progress",
                "--threads", "\(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))"
            ]

            if let lang = language, lang != "auto" {
                args += ["--language", lang]
            }

            process.arguments = args
            print("whisper_debug: 🚀 Running: \(binary) \(args.joined(separator: " "))")

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Thread-safe accumulator for stdout data
            // readabilityHandler consumes data from the pipe — we MUST accumulate it
            // because readDataToEndOfFile() after readabilityHandler returns empty.
            let lock = NSLock()
            var outputAccumulator = Data()
            var errorAccumulator = Data()

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                outputAccumulator.append(chunk)
                lock.unlock()
                
                // Parse progress from stdout (some whisper versions output here)
                if let text = String(data: chunk, encoding: .utf8) {
                    let lines = text.components(separatedBy: .newlines)
                    for line in lines where line.contains("progress =") {
                        if let percent = self.extractProgress(from: line) {
                            let totalProgress = 0.15 + (percent * 0.85)
                            var remainingTime: TimeInterval?
                            if totalProgress > 0.20 {
                                let elapsed = Date().timeIntervalSince(startTime)
                                let estimatedTotal = elapsed / Double(totalProgress)
                                remainingTime = max(0, estimatedTotal - elapsed)
                            }
                            onProgress?(totalProgress, remainingTime)
                        }
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                errorAccumulator.append(chunk)
                lock.unlock()
                
                // Parse progress from stderr (some whisper versions output here)
                if let text = String(data: chunk, encoding: .utf8) {
                    let lines = text.components(separatedBy: .newlines)
                    for line in lines where line.contains("progress =") {
                        if let percent = self.extractProgress(from: line) {
                            let totalProgress = 0.15 + (percent * 0.85)
                            var remainingTime: TimeInterval?
                            if totalProgress > 0.20 {
                                let elapsed = Date().timeIntervalSince(startTime)
                                let estimatedTotal = elapsed / Double(totalProgress)
                                remainingTime = max(0, estimatedTotal - elapsed)
                            }
                            onProgress?(totalProgress, remainingTime)
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] p in
                self?.currentProcess = nil
                // Drain any remaining data
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                // Small delay to let final readability callbacks flush
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    lock.lock()
                    let finalOutput = outputAccumulator
                    let finalError = errorAccumulator
                    lock.unlock()
                    
                    if p.terminationStatus == 0 {
                        let output = String(data: finalOutput, encoding: .utf8) ?? ""
                        print("whisper_debug: 📦 Accumulated \(finalOutput.count) bytes from stdout")
                        let text = self?.parseWhisperOutput(output) ?? ""
                        continuation.resume(returning: text)
                    } else {
                        let errorOutput = String(data: finalError, encoding: .utf8) ?? "Unknown error"
                        print("whisper_debug: ❌ whisper-cli failed (status \(p.terminationStatus)): \(errorOutput)")
                        continuation.resume(throwing: TranscriptionError.transcriptionFailed(errorOutput))
                    }
                }
            }

            do {
                try process.run()
                // Immediately report small progress to show "Initializing" state
                onProgress?(0.12, nil)
            } catch {
                continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    private func findWhisperBinary() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/main",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/main",
            "/usr/bin/whisper-cli",
            "/usr/bin/whisper-cpp",
            "/usr/bin/whisper"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
            // Try resolving symlinks as a fallback
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if url.path != path {
                if FileManager.default.fileExists(atPath: url.path) && FileManager.default.isExecutableFile(atPath: url.path) {
                    return url.path
                }
            }
        }

        // Try `which` for both names as fallback
        for name in ["whisper-cli", "whisper-cpp", "main"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [name]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func convertTo16kHzWav(_ inputURL: URL, onProgress: @escaping (Float) -> Void) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_input_\(UUID().uuidString).wav")

        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration).seconds
        
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

        final class ConversionContext: @unchecked Sendable {
            let reader: AVAssetReader
            let writer: AVAssetWriter
            let writerInput: AVAssetWriterInput
            let trackOutput: AVAssetReaderTrackOutput
            let duration: Double
            var isResumed = false
            
            init(reader: AVAssetReader, writer: AVAssetWriter, writerInput: AVAssetWriterInput, trackOutput: AVAssetReaderTrackOutput, duration: Double) {
                self.reader = reader
                self.writer = writer
                self.writerInput = writerInput
                self.trackOutput = trackOutput
                self.duration = duration
            }
        }
        
        let context = ConversionContext(reader: reader, writer: writer, writerInput: writerInput, trackOutput: trackOutput, duration: duration)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "audioConvertQueue")
            
            context.writerInput.requestMediaDataWhenReady(on: queue) {
                while context.writerInput.isReadyForMoreMediaData {
                    if let buffer = context.trackOutput.copyNextSampleBuffer() {
                        let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                        let progress = Float(time / context.duration)
                        onProgress(progress)
                        
                        context.writerInput.append(buffer)
                    } else {
                        if !context.isResumed {
                            context.isResumed = true
                            context.writerInput.markAsFinished()
                            
                            if let error = context.reader.error ?? context.writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                        break
                    }
                }
            }
        }
        
        await writer.finishWriting()
        onProgress(1.0)
        return outputURL
    }

    // MARK: - Check if already 16kHz WAV
    
    private func isAlready16kHzWav(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let is16k = abs(format.sampleRate - 16000) < 100 // tolerance
            let isMono = format.channelCount == 1
            print("whisper_debug: File check: \(url.lastPathComponent) → \(format.sampleRate)Hz, \(format.channelCount)ch → skip=\(is16k && isMono)")
            return is16k && isMono
        } catch {
            print("whisper_debug: Cannot read audio file for format check: \(error)")
            return false
        }
    }

    // MARK: - Parse output

    private func parseWhisperOutput(_ raw: String) -> String {
        print("whisper_debug: 🔍 Raw whisper-cli output (\(raw.count) chars):")
        print("whisper_debug: ---BEGIN---")
        print(raw)
        print("whisper_debug: ---END---")
        
        let lines = raw.components(separatedBy: .newlines)
        let textLines = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.hasPrefix("whisper_") && !$0.hasPrefix("main:") && !$0.contains("progress =") }

        let result = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        print("whisper_debug: 📝 Parsed result: '\(result)' (kept \(textLines.count)/\(lines.count) lines)")
        return result
    }

    private func extractProgress(from line: String) -> Float? {
        // Look for "progress = 42%" or "[ 42%] progress = 42%"
        // Using a simpler but more robust split search if regex is overkill
        if let progressPart = line.components(separatedBy: "progress =").last?.trimmingCharacters(in: .whitespaces),
           let percentStr = progressPart.components(separatedBy: "%").first,
           let percent = Float(percentStr.trimmingCharacters(in: .whitespaces)) {
            return percent / 100.0
        }
        
        // Fallback to regex for patterns like "[ 42%]"
        let pattern = "(\\d+)%"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: nsRange) {
                if let range = Range(match.range(at: 1), in: line),
                   let percent = Float(line[range]) {
                    return percent / 100.0
                }
            }
        }
        return nil
    }
}
