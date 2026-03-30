import Foundation
@preconcurrency import AVFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CloudWhisper: TranscriptionEngine {
    private let apiKey: String
    private let maxUploadBytes = 25 * 1024 * 1024 // OpenAI 25 MB limit
    /// Maximum chunk duration in seconds for splitting large files (10 minutes)
    private let maxChunkDuration: TimeInterval = 600

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public API

    func transcribe(audioURL: URL, language: String?, timeRange: CMTimeRange? = nil, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let startTime = Date()

        // Stage 1: Prepare the file (0–10%)
        onProgress?(0.02, nil)
        
        let (uploadURL, shouldCleanup) = try await prepareAudioFile(audioURL, timeRange: timeRange, onProgress: onProgress)
        defer { if shouldCleanup { try? FileManager.default.removeItem(at: uploadURL) } }

        // Check if we need to chunk (file too large or too long)
        let asset = AVURLAsset(url: uploadURL)
        let totalDuration = try await asset.load(.duration).seconds
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int) ?? 0

        if fileSize > maxUploadBytes || totalDuration > maxChunkDuration {
            print("whisper_debug: ☁️ File needs chunking: \(fileSize) bytes, \(String(format: "%.0f", totalDuration))s duration")
            let result = try await transcribeInChunks(fileURL: uploadURL, totalDuration: totalDuration, language: language, startTime: startTime, onProgress: onProgress)
            onProgress?(1.0, nil)
            return result
        }

        // Single-file upload path
        let text = try await uploadAndTranscribe(fileURL: uploadURL, language: language, onProgress: onProgress, progressRange: (0.10, 0.90))

        let elapsed = Date().timeIntervalSince(startTime)
        print("whisper_debug: ☁️ Transcription complete in \(String(format: "%.1f", elapsed))s")
        onProgress?(1.0, nil)

        return text
    }

    // MARK: - Chunked Transcription

    /// Splits a long audio file into chunks and transcribes each one sequentially.
    private func transcribeInChunks(fileURL: URL, totalDuration: TimeInterval, language: String?, startTime: Date, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String {
        let chunkCount = Int(ceil(totalDuration / maxChunkDuration))
        print("whisper_debug: ☁️ Splitting into \(chunkCount) chunks of \(Int(maxChunkDuration))s each")

        var allTexts: [String] = []

        for i in 0..<chunkCount {
            let chunkStart = TimeInterval(i) * maxChunkDuration
            let chunkEnd = min(chunkStart + maxChunkDuration, totalDuration)
            let chunkProgress = Float(i) / Float(chunkCount)
            let nextChunkProgress = Float(i + 1) / Float(chunkCount)

            print("whisper_debug: ☁️ Chunk \(i + 1)/\(chunkCount): \(String(format: "%.0f", chunkStart))s – \(String(format: "%.0f", chunkEnd))s")

            // Map overall progress: 10% to 95% across all chunks
            let overallStart = 0.10 + chunkProgress * 0.85
            let overallEnd = 0.10 + nextChunkProgress * 0.85
            onProgress?(overallStart, nil)

            // Export this chunk
            let chunkURL = try await exportChunk(from: fileURL, start: chunkStart, end: chunkEnd)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            let chunkSize = (try? FileManager.default.attributesOfItem(atPath: chunkURL.path)[.size] as? Int) ?? 0
            print("whisper_debug: ☁️ Chunk \(i + 1) size: \(chunkSize) bytes")

            let text = try await uploadAndTranscribe(fileURL: chunkURL, language: language, onProgress: onProgress, progressRange: (overallStart, overallEnd))
            if !text.isEmpty {
                allTexts.append(text)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("whisper_debug: ☁️ Chunked transcription complete in \(String(format: "%.1f", elapsed))s (\(chunkCount) chunks)")

        return allTexts.joined(separator: "\n\n")
    }

    /// Export a time-range chunk from an audio file using AVAssetExportSession.
    private func exportChunk(from fileURL: URL, start: TimeInterval, end: TimeInterval) async throws -> URL {
        let asset = AVURLAsset(url: fileURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_\(UUID().uuidString).m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.transcriptionFailed("Cannot create export session for chunking")
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 44100),
            end: CMTime(seconds: end, preferredTimescale: 44100)
        )

        await session.export()

        if let error = session.error {
            throw TranscriptionError.transcriptionFailed("Chunk export failed: \(error.localizedDescription)")
        }

        guard session.status == .completed else {
            throw TranscriptionError.transcriptionFailed("Chunk export ended with status: \(session.status.rawValue)")
        }

        return outputURL
    }

    // MARK: - Single Upload

    /// Uploads a single audio file to OpenAI Whisper API and returns the text.
    private func uploadAndTranscribe(fileURL: URL, language: String?, onProgress: ((Float, TimeInterval?) -> Void)?, progressRange: (Float, Float)) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")
        
        // Suppress hallucinations (Subeditor credits, "To be continued" repetitions)
        let suppressionPrompt = "Чистая расшифровка разговора без указания редакторов, корректоров и субтитров. Не писать слово 'Продолжение следует'. Clean transcription without any subeditor or proofreader credits."
        body.appendMultipart(boundary: boundary, name: "prompt", value: suppressionPrompt)
        
        if let lang = language, lang != "auto" {
            body.appendMultipart(boundary: boundary, name: "language", value: lang)
        }
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")

        let audioData = try Data(contentsOf: fileURL)
        let ext = fileURL.pathExtension.lowercased()
        let (fileName, mimeType) = Self.fileInfo(for: ext)
        body.appendMultipart(boundary: boundary, name: "file", fileName: fileName, mimeType: mimeType, fileData: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("whisper_debug: ☁️ Uploading \(audioData.count) bytes (\(ext)) to OpenAI Whisper API...")
        onProgress?(progressRange.0 + (progressRange.1 - progressRange.0) * 0.3, nil)

        let (data, response) = try await URLSession.shared.data(for: request)

        onProgress?(progressRange.1, nil)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid API key. Please check your OpenAI API key in Settings → Engine & API.")
        }

        if httpResponse.statusCode == 429 {
            let errorText = openAIErrorMessage(from: data) ?? "OpenAI quota exceeded. Check billing and project limits."
            throw TranscriptionError.networkError(errorText)
        }

        if httpResponse.statusCode != 200 {
            let errorText = openAIErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TranscriptionError.invalidResponse
        }

        return text
    }

    private func openAIErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    // MARK: - File Preparation

    /// Prepares the audio file for upload, extracting audio from video or compressing if too large.
    /// Returns (URL to upload, shouldCleanup).
    private func prepareAudioFile(_ inputURL: URL, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> (URL, Bool) {
        let ext = inputURL.pathExtension.lowercased()
        let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm"])
        let isVideo = videoExtensions.contains(ext)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int) ?? 0

        if !isVideo && fileSize < maxUploadBytes && timeRange == nil {
            // Small audio file and no trimming — upload directly
            print("whisper_debug: ☁️ File is small audio (\(fileSize) bytes), uploading directly")
            return (inputURL, false)
        }

        // Extract audio track using AVAssetExportSession (reliable for all codecs)
        print("whisper_debug: ☁️ Extracting/compressing audio from \(ext) file (\(fileSize) bytes)...")
        let outputURL = try await extractAudioAsM4A(inputURL, timeRange: timeRange, onProgress: onProgress)
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("whisper_debug: ☁️ Extracted audio: \(outputSize) bytes")

        return (outputURL, true)
    }

    /// Extracts audio from any media file using AVAssetExportSession (reliable, handles all codecs).
    private func extractAudioAsM4A(_ inputURL: URL, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud_audio_\(UUID().uuidString).m4a")

        let asset = AVURLAsset(url: inputURL)

        // Verify that there is an audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.transcriptionFailed("No audio track found in file")
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.transcriptionFailed("Cannot create AVAssetExportSession")
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a
        
        if let range = timeRange {
            session.timeRange = range
        }

        // Report progress during extraction
        let progressTask = Task {
            while !Task.isCancelled {
                let p = session.progress
                // Map extraction to 2–10% of total progress
                onProgress?(0.02 + p * 0.08, nil)
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }

        await session.export()
        progressTask.cancel()

        if let error = session.error {
            throw TranscriptionError.transcriptionFailed("Audio extraction failed: \(error.localizedDescription)")
        }

        guard session.status == .completed else {
            throw TranscriptionError.transcriptionFailed("Audio extraction ended with status: \(session.status.rawValue)")
        }

        onProgress?(0.10, nil)
        return outputURL
    }

    // MARK: - Helpers

    private static func fileInfo(for ext: String) -> (fileName: String, mimeType: String) {
        switch ext {
        case "mp3":  return ("audio.mp3", "audio/mpeg")
        case "mp4":  return ("audio.mp4", "audio/mp4")
        case "m4a":  return ("audio.m4a", "audio/mp4")
        case "wav":  return ("audio.wav", "audio/wav")
        case "webm": return ("audio.webm", "audio/webm")
        case "ogg":  return ("audio.ogg", "audio/ogg")
        case "flac": return ("audio.flac", "audio/flac")
        default:     return ("audio.\(ext)", "application/octet-stream")
        }
    }

    /// Returns the duration of an audio/video file in seconds.
    static func fileDuration(url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        return try? await asset.load(.duration).seconds
    }
}

// MARK: - Multipart Form Data Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, fileName: String, mimeType: String, fileData: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
