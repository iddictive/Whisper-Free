import Foundation

enum PostProcessingEngine: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case perplexity = "Perplexity"
}

// MARK: - Transcription Mode

struct TranscriptionMode: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let icon: String
    let description: String
    let exampleInput: String
    let exampleOutput: String
    let systemPrompt: String
    let isBuiltIn: Bool

    static let dictation = TranscriptionMode(
        name: "Dictation",
        icon: "text.bubble",
        description: "Fixes grammar and removes filler words while keeping the exact original meaning.",
        exampleInput: "So um I think that we should like probably go to the meeting or something you know.",
        exampleOutput: "I think that we should go to the meeting.",
        systemPrompt: """
        Clean up this transcribed speech. Remove filler words (um, uh, like, you know), \
        fix grammar, add proper punctuation and capitalization. Keep the original meaning \
        and tone. Output ONLY the cleaned text, nothing else.
        """,
        isBuiltIn: true
    )

    static let email = TranscriptionMode(
        name: "Email",
        icon: "envelope",
        description: "Formats speech into a professional email with greetings and a clear structure.",
        exampleInput: "Tell John that I finished the report and I will send it by five pm today thanks.",
        exampleOutput: "Hi John,\n\nI have finished the report and will send it to you by 5:00 PM today.\n\nBest regards,",
        systemPrompt: """
        Format this transcribed speech as a professional email. Clean up filler words, \
        fix grammar, add proper greeting and sign-off if not present. Keep a professional \
        but friendly tone. Output ONLY the formatted email text, nothing else.
        """,
        isBuiltIn: true
    )

    static let code = TranscriptionMode(
        name: "Code",
        icon: "chevron.left.forwardslash.chevron.right",
        description: "Converts ideas into clean code comments or technical documentation.",
        exampleInput: "This function basically calculates the total price by adding tax to the base amount.",
        exampleOutput: "// Calculates total price by applying tax to base amount",
        systemPrompt: """
        Convert this transcribed speech into code comments or documentation. Format as \
        proper code comments (// or /* */). Clean up filler words, be concise and technical. \
        Output ONLY the code comments, nothing else.
        """,
        isBuiltIn: true
    )

    static let notes = TranscriptionMode(
        name: "Notes",
        icon: "list.bullet",
        description: "Extracts key points and organizes them into a clean markdown list.",
        exampleInput: "We need to buy milk eggs and bread also don't forget to call mom at six.",
        exampleOutput: "• Buy milk, eggs, and bread\n• Call mom at 6:00 PM",
        systemPrompt: """
        Convert this transcribed speech into organized bullet-point notes. Extract key \
        points, organize logically, remove filler words. Use markdown bullet points. \
        Output ONLY the formatted notes, nothing else.
        """,
        isBuiltIn: true
    )

    static let builtInModes: [TranscriptionMode] = [.dictation, .email, .code, .notes]
    
    // Placeholder values for UI creation
    static let placeholderName = "Summary"
    static let placeholderDescription = "Extracts key points into a short summary."
    static let placeholderExampleInput = "So we talked about the budget and we decided to increase it by 10% next quarter."
    static let placeholderExampleOutput = "Budget increased by 10% for the next quarter."
    static let placeholderPrompt = "Summarize this transcription professionally. Focus on decisions and actions."
}

// MARK: - Usage & History
    
struct UsageLog: Codable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    let modeName: String
    let engine: String // "openai", "perplexity", "local"
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let estimatedCost: Double
    
    // Estimates based on gpt-4o-mini ($0.15 / 1M input, $0.60 / 1M output)
    static func estimateCost(prompt: Int, completion: Int, engine: PostProcessingEngine) -> Double {
        let pRate = 0.15 / 1_000_000.0
        let cRate = 0.60 / 1_000_000.0
        return (Double(prompt) * pRate) + (Double(completion) * cRate)
    }
}

struct TranscriptionHistoryEntry: Codable {
    let entryId: UUID
    let date: Date
    let rawText: String
    let processedText: String
    let modeName: String
    let duration: TimeInterval
    let engineUsed: String
    var usage: UsageLog?

    init(rawText: String, processedText: String, modeName: String, duration: TimeInterval, engineUsed: String, usage: UsageLog? = nil) {
        self.entryId = UUID()
        self.date = Date()
        self.rawText = rawText
        self.processedText = processedText
        self.modeName = modeName
        self.duration = duration
        self.engineUsed = engineUsed
        self.usage = usage
    }
}

// MARK: - Recording Mode

enum RecordingMode: String, Codable, CaseIterable {
    case hold = "Hold to Record"
    case toggle = "Toggle"
    case pushToTalk = "Push to Talk"

    var description: String {
        switch self {
        case .hold: return "Hold ⌥+Space to record, release to transcribe"
        case .toggle: return "Press ⌥+Space to start, press again to stop"
        case .pushToTalk: return "Hold ⌥+Space (300ms+) to record, release to transcribe"
        }
    }

    var icon: String {
        switch self {
        case .hold: return "hand.tap"
        case .toggle: return "arrow.triangle.2.circlepath"
        case .pushToTalk: return "mic.badge.plus"
        }
    }
}

// MARK: - Insertion Method

enum InsertionMethod: String, Codable, CaseIterable {
    case paste = "Paste (Clipboard)"
    case type = "Direct Typing (No Clipboard)"
    
    var icon: String {
        switch self {
        case .paste: return "doc.on.clipboard"
        case .type: return "keyboard"
        }
    }
}

// MARK: - Transcription Engine Type

enum TranscriptionEngineType: String, Codable, CaseIterable {
    case cloud = "Cloud (OpenAI)"
    case local = "Local (whisper.cpp)"

    var icon: String {
        switch self {
        case .cloud: return "cloud"
        case .local: return "desktopcomputer"
        }
    }
}

// MARK: - Local Model Size

enum LocalModelSize: String, Codable, CaseIterable {
    case tiny = "Tiny"
    case base = "Base"
    case small = "Small"
    case medium = "Medium"
    case largeV3Turbo = "Large v3 Turbo"
    case largeV3 = "Large v3"

    var fileName: String {
        switch self {
        case .tiny: return "ggml-tiny.bin"
        case .base: return "ggml-base.bin"
        case .small: return "ggml-small.bin"
        case .medium: return "ggml-medium.bin"
        case .largeV3Turbo: return "ggml-large-v3-turbo.bin"
        case .largeV3: return "ggml-large-v3.bin"
        }
    }

    var downloadURL: URL {
        let base = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
        return URL(string: "\(base)/\(fileName)") ?? URL(string: "https://huggingface.co")!
    }

    var sizeDescription: String {
        switch self {
        case .tiny: return "~75 MB · Fastest, basic accuracy"
        case .base: return "~140 MB · Good for quick tasks"
        case .small: return "~460 MB · Solid accuracy"
        case .medium: return "~1.5 GB · High accuracy"
        case .largeV3Turbo: return "~1.6 GB · Best speed/quality"
        case .largeV3: return "~3.1 GB · Maximum accuracy"
        }
    }

    var qualityStars: Int {
        switch self {
        case .tiny: return 1
        case .base: return 2
        case .small: return 3
        case .medium: return 4
        case .largeV3Turbo: return 4
        case .largeV3: return 5
        }
    }

    var speedRating: String {
        switch self {
        case .tiny: return "⚡⚡⚡"
        case .base: return "⚡⚡⚡"
        case .small: return "⚡⚡"
        case .medium: return "⚡⚡"
        case .largeV3Turbo: return "⚡⚡"
        case .largeV3: return "⚡"
        }
    }

    /// Recommended model based on available RAM
    static var recommended: LocalModelSize {
        let ram = ProcessInfo.processInfo.physicalMemory
        if ram >= 32 * 1024 * 1024 * 1024 { return .largeV3Turbo }
        if ram >= 16 * 1024 * 1024 * 1024 { return .medium }
        return .small
    }
}

// MARK: - App Settings

// MARK: - Hotkey Config

struct HotkeyConfig: Codable, Equatable, Hashable {
    var keyCode: Int = 49        // Space
    var useOption: Bool = true
    var useCommand: Bool = false
    var useControl: Bool = false
    var useShift: Bool = false

    enum CodingKeys: String, CodingKey {
        case keyCode, useOption, useCommand, useControl, useShift
    }

    init() {}

    init(keyCode: Int, useOption: Bool = false, useCommand: Bool = false, useControl: Bool = false, useShift: Bool = false) {
        self.keyCode = keyCode
        self.useOption = useOption
        self.useCommand = useCommand
        self.useControl = useControl
        self.useShift = useShift
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode) ?? 49
        useOption = try container.decodeIfPresent(Bool.self, forKey: .useOption) ?? true
        useCommand = try container.decodeIfPresent(Bool.self, forKey: .useCommand) ?? false
        useControl = try container.decodeIfPresent(Bool.self, forKey: .useControl) ?? false
        useShift = try container.decodeIfPresent(Bool.self, forKey: .useShift) ?? false
    }

    var displayString: String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useOption  { parts.append("⌥") }
        if useShift   { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined(separator: " ")
    }

    var keyName: String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 51: return "Delete"
        case 50: return "`"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        // Letters
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        // F-keys
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        default: return "Key(\(keyCode))"
        }
    }

    static let presets: [(name: String, config: HotkeyConfig)] = [
        ("⌥ Space", HotkeyConfig(keyCode: 49, useOption: true)),
        ("Dictation Key (F5)", HotkeyConfig(keyCode: 96, useOption: false)),
        ("⌘ ⇧ Space", HotkeyConfig(keyCode: 49, useOption: false, useCommand: true, useShift: true)),
        ("⌃ Space", HotkeyConfig(keyCode: 49, useOption: false, useControl: true)),
        ("⌥ Return", HotkeyConfig(keyCode: 36, useOption: true)),
        ("⌥ `", HotkeyConfig(keyCode: 50, useOption: true)),
    ]
}


struct AppSettings: Codable {
    var apiKey: String = ""
    var perplexityApiKey: String = ""
    var postProcessingEngine: PostProcessingEngine = .openai
    var autoTypeResult: Bool = true
    var language: String = "auto"
    var selectedModeName: String = TranscriptionMode.dictation.name
    var customModes: [TranscriptionMode] = []
    var recordingMode: RecordingMode = .hold
    var engineType: TranscriptionEngineType = .cloud
    var localModelSize: LocalModelSize = .base
    var showOverlay: Bool = true
    var setupCompleted: Bool = false
    var hotkeyConfig: HotkeyConfig = HotkeyConfig()
    var insertionMethod: InsertionMethod = .type
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = true
    var enablePostProcessing: Bool = true
    var useMonochromeMenuIcon: Bool = false
    var usageLogs: [UsageLog] = []
    var experimentalAutoEnter: Bool = false

    enum CodingKeys: String, CodingKey {
        case apiKey, perplexityApiKey, postProcessingEngine, autoTypeResult, language,
             selectedModeName, customModes, recordingMode, engineType, localModelSize,
             showOverlay, setupCompleted, hotkeyConfig, insertionMethod,
             automaticallyChecksForUpdates, automaticallyDownloadsUpdates,
             enablePostProcessing, useMonochromeMenuIcon, usageLogs, experimentalAutoEnter
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        perplexityApiKey = try container.decodeIfPresent(String.self, forKey: .perplexityApiKey) ?? ""
        postProcessingEngine = try container.decodeIfPresent(PostProcessingEngine.self, forKey: .postProcessingEngine) ?? .openai
        autoTypeResult = try container.decodeIfPresent(Bool.self, forKey: .autoTypeResult) ?? true
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        selectedModeName = try container.decodeIfPresent(String.self, forKey: .selectedModeName) ?? TranscriptionMode.dictation.name
        customModes = try container.decodeIfPresent([TranscriptionMode].self, forKey: .customModes) ?? []
        recordingMode = try container.decodeIfPresent(RecordingMode.self, forKey: .recordingMode) ?? .hold
        engineType = try container.decodeIfPresent(TranscriptionEngineType.self, forKey: .engineType) ?? .cloud
        localModelSize = try container.decodeIfPresent(LocalModelSize.self, forKey: .localModelSize) ?? .base
        showOverlay = try container.decodeIfPresent(Bool.self, forKey: .showOverlay) ?? true
        setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? false
        hotkeyConfig = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkeyConfig) ?? HotkeyConfig()
        insertionMethod = try container.decodeIfPresent(InsertionMethod.self, forKey: .insertionMethod) ?? .type
        automaticallyChecksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
        automaticallyDownloadsUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyDownloadsUpdates) ?? true
        enablePostProcessing = try container.decodeIfPresent(Bool.self, forKey: .enablePostProcessing) ?? true
        useMonochromeMenuIcon = try container.decodeIfPresent(Bool.self, forKey: .useMonochromeMenuIcon) ?? false
        usageLogs = try container.decodeIfPresent([UsageLog].self, forKey: .usageLogs) ?? []
        experimentalAutoEnter = try container.decodeIfPresent(Bool.self, forKey: .experimentalAutoEnter) ?? false
    }

    var allModes: [TranscriptionMode] {
        TranscriptionMode.builtInModes + customModes
    }

    var selectedMode: TranscriptionMode {
        allModes.first { $0.name == selectedModeName } ?? .dictation
    }

    func isModeEnabled(_ mode: TranscriptionMode) -> Bool {
        // Dictation is the fallback, always technically "on" but skips AI if no key
        if mode.name == TranscriptionMode.dictation.name { return true }
        
        // AI modes require global enablement AND keys
        guard enablePostProcessing else { return false }
        
        switch postProcessingEngine {
        case .openai:
            return !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        case .perplexity:
            return !perplexityApiKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func validatedModeName(currentName: String) -> String {
        let currentMode = allModes.first { $0.name == currentName } ?? .dictation
        if !isModeEnabled(currentMode) {
            return TranscriptionMode.dictation.name
        }
        return currentName
    }

    // Supported languages for Whisper
    static let supportedLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("nl", "Dutch"),
        ("sv", "Swedish"),
        ("uk", "Ukrainian"),
    ]
}
