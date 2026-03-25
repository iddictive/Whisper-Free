import Foundation

enum LocalTranslationError: Error, LocalizedError {
    case notRunning
    case pullFailed(String)
    case translationFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notRunning: return "Ollama is not running. Please install and start Ollama (http://localhost:11434)."
        case .pullFailed(let msg): return "Failed to download model: \(msg)"
        case .translationFailed(let msg): return "Translation failed: \(msg)"
        case .invalidResponse: return "Invalid response from Ollama API."
        }
    }
}

final class LocalTranslationEngine {
    private let baseURL = URL(string: "http://localhost:11434/api")!
    
    // Check if Ollama is running
    func isRunning() async -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:11434/")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // Check if a specific model exists
    func checkModelExists(name: String) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return false }
            
            return models.contains { ($0["name"] as? String) == name || ($0["name"] as? String)?.hasPrefix(name + ":") == true }
        } catch {
            return false
        }
    }
    
    // Pull model
    func pullModel(name: String, progressHandler: @escaping (String) -> Void) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["name": name]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LocalTranslationError.pullFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        var lastStatus = ""
        var lastPercentage = -1
        
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            
            let status = json["status"] as? String ?? ""
            let total = json["total"] as? Int64 ?? 0
            let completed = json["completed"] as? Int64 ?? 0
            
            var progressString = status
            
            if total > 0 {
                let percentage = Int((Double(completed) / Double(total)) * 100)
                progressString += " (\(formatBytes(completed)) / \(formatBytes(total)) - \(percentage)%)"
                
                // Only update if percentage or status changed significantly to avoid UI thrashing
                if status != lastStatus || percentage != lastPercentage {
                    progressHandler(progressString)
                    lastStatus = status
                    lastPercentage = percentage
                }
            } else if status != lastStatus {
                progressHandler(status)
                lastStatus = status
            }
        }
    }
    
    // Translate text
    func translate(text: String, targetLanguage: String, model: String) async throws -> String {
        let systemPrompt = "You are a professional real-time translator. Translate the following transcription into \(targetLanguage). Ensure the translation sounds natural in \(targetLanguage). Provide ONLY the translation without any explanations, comments, or conversational text. Never output any markdown formatting."
        return try await chat(systemPrompt: systemPrompt, userText: text, model: model, temperature: 0.3)
    }

    func chat(systemPrompt: String, userText: String, model: String, temperature: Double = 0.3) async throws -> String {
        guard await isRunning() else {
            throw LocalTranslationError.notRunning
        }

        guard await checkModelExists(name: model) else {
            throw LocalTranslationError.translationFailed("Model '\(model)' is not available in Ollama. Download it in Live Translator settings first.")
        }
        
        var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ],
            "stream": false,
            "options": [
                "temperature": temperature
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown HTTP Response Code"
            throw LocalTranslationError.translationFailed(errorText)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LocalTranslationError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Helper to format bytes
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Check local models
    func getLocalModels() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        
        return models.compactMap { $0["name"] as? String }
    }
}
