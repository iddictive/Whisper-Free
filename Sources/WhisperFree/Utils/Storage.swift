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

    func updateSettings(_ block: (inout AppSettings) -> Void) {
        var settings = loadSettings()
        block(&settings)
        saveSettings(settings)
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
            let toDelete = history.suffix(from: 500)
            for entry in toDelete {
                if entry.ownsAudioFile, let path = entry.audioFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            history = Array(history.prefix(500))
        }
        saveHistory(history)
    }

    func deleteTranscriptionHistoryEntry(id: UUID) {
        var history = loadHistory()
        if let entry = history.first(where: { $0.entryId == id }) {
            if entry.ownsAudioFile, let path = entry.audioFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        history.removeAll { entry in entry.entryId == id }
        saveHistory(history)
    }

    func updateTranscriptionHistoryEntry(_ entry: TranscriptionHistoryEntry) {
        var history = loadHistory()
        if let index = history.firstIndex(where: { $0.entryId == entry.entryId }) {
            history[index] = entry
            saveHistory(history)
        }
    }

    func clearHistory() {
        let history = loadHistory()
        for entry in history {
            if entry.ownsAudioFile, let path = entry.audioFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        saveHistory([])
    }

    func applyRetentionPolicy(_ policy: AudioRetentionPolicy) {
        guard let days = policy.days else { return } // Forever
        
        let now = Date()
        let history = loadHistory()
        var newHistory: [TranscriptionHistoryEntry] = []
        
        for entry in history {
            let diff = Calendar.current.dateComponents([.day], from: entry.date, to: now).day ?? 0
            if diff >= days {
                // Delete audio file
                if entry.ownsAudioFile, let path = entry.audioFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                // Do not add to newHistory
            } else {
                newHistory.append(entry)
            }
        }
        
        if newHistory.count != history.count {
            saveHistory(newHistory)
            print("whisper_debug: 🧹 Applied retention policy (\(policy.rawValue)): removed \(history.count - newHistory.count) entries.")
        }
    }

    // MARK: - Models directory

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WhisperKiller/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WhisperKiller/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
