import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CloudWhisper: TranscriptionEngine {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioURL: URL, language: String?, onProgress: ((Float) -> Void)?) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")

        // Language field (if not auto)
        if let lang = language, lang != "auto" {
            body.appendMultipart(boundary: boundary, name: "language", value: lang)
        }

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")

        // Audio file
        let audioData = try Data(contentsOf: audioURL)
        body.appendMultipart(boundary: boundary, name: "file", fileName: "recording.wav", mimeType: "audio/wav", fileData: audioData)

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid API Key. Please check your OpenAI API key in Settings → General.")
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("HTTP \(httpResponse.statusCode): \(errorText)")
        }

        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TranscriptionError.invalidResponse
        }

        return text
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
