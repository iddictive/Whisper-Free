import Foundation

// MARK: - Settings Storage

final class Storage {
    static let shared = Storage()

    private let settingsKey = "SuperWhisperSettings"
    private let historyKey = "SuperWhisperHistory"

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            return AppSettings()
        }
        
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            print("⚠️ Error decoding settings: \(error)")
            // If decoding fails, we still return AppSettings() to avoid crashing,
            // but now we at least know why it happened.
            return AppSettings()
        }
    }

    func saveSettings(_ settings: AppSettings) {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    // MARK: - History

    func loadHistory() -> [TranscriptionHistoryEntry] {
        guard let data = defaults.data(forKey: historyKey),
              let history = try? decoder.decode([TranscriptionHistoryEntry].self, from: data)
        else {
            return []
        }
        return history
    }

    func saveHistory(_ history: [TranscriptionHistoryEntry]) {
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    func addTranscriptionHistoryEntry(_ entry: TranscriptionHistoryEntry) {
        var history = loadHistory()
        history.insert(entry, at: 0)
        // Keep last 500 entries
        if history.count > 500 {
            history = Array(history.prefix(500))
        }
        saveHistory(history)
    }

    func deleteTranscriptionHistoryEntry(id: UUID) {
        var history = loadHistory()
        history.removeAll { entry in entry.entryId == id }
        saveHistory(history)
    }

    func clearHistory() {
        saveHistory([])
    }

    // MARK: - Models directory

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WhisperKiller/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
