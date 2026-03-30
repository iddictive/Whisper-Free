import Foundation
import CoreMedia

// MARK: - Transcription Engine Protocol

protocol TranscriptionEngine {
    func transcribe(audioURL: URL, language: String?, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String
    func pause()
    func resume()
    func cancel()
}

extension TranscriptionEngine {
    func pause() {}
    func resume() {}
    func cancel() {}
}

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(String)
    case modelNotDownloaded
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your OpenAI API key in Settings → Engine & API."
        case .invalidResponse:
            return "Invalid response from transcription service."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .modelNotDownloaded:
            return "Local model not downloaded. Please download a model in Settings → Engine."
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}

// MARK: - Engine Factory

struct TranscriptionEngineFactory {
    static func create(for type: TranscriptionEngineType, settings: AppSettings) -> TranscriptionEngine {
        switch type {
        case .cloud:
            return CloudWhisper(apiKey: settings.normalizedAPIKey)
        case .local:
            return LocalWhisper(modelSize: settings.localModelSize)
        }
    }
}
