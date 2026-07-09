import Foundation

// MARK: - App Language

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case luxembourgish = "lb"
    case german = "de"
    case french = "fr"
    case english = "en"
    case portuguese = "pt"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .luxembourgish: return "Lëtzebuergesch"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .english: return "English"
        case .portuguese: return "Português"
        }
    }
    
    var flag: String {
        switch self {
        case .luxembourgish: return "🇱🇺"
        case .german: return "🇩🇪"
        case .french: return "🇫🇷"
        case .english: return "🇬🇧"
        case .portuguese: return "🇵🇹"
        }
    }
    
    /// ISO 639-3 code for ElevenLabs
    var elevenLabsCode: String {
        switch self {
        case .luxembourgish: return "ltz"
        case .german: return "deu"
        case .french: return "fra"
        case .english: return "eng"
        case .portuguese: return "por"
        }
    }
}

// MARK: - Output Type

enum OutputType: String, Codable, CaseIterable, Identifiable, Sendable {
    case meetingNotes = "meeting"
    case brainstorm = "brainstorm"
    case personalMemo = "memo"
    case clientCall = "client_call"
    case interview = "interview"
    case taskList = "task_list"
    case cleanResume = "resume"
    case rawTranscript = "raw"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .meetingNotes: return "Meeting Notes"
        case .brainstorm: return "Brainstorm"
        case .personalMemo: return "Personal Memo"
        case .clientCall: return "Client Call"
        case .interview: return "Interview"
        case .taskList: return "Task List"
        case .cleanResume: return "Clean Résumé"
        case .rawTranscript: return "Raw Transcript Only"
        }
    }
}

// MARK: - Note Status

enum NoteStatus: String, Codable, Sendable {
    case draft
    case processing
    case ready
    case failed
}

enum ProcessingStage: String, Codable, Sendable, CaseIterable {
    case savingAudio = "saving"
    case transcribing = "transcribing"
    case checkingQuality = "checking"
    case summarizing = "summarizing"
    case ready = "ready"
    
    var displayName: String {
        switch self {
        case .savingAudio: return "Saving audio"
        case .transcribing: return "Transcribing"
        case .checkingQuality: return "Checking quality"
        case .summarizing: return "Summarizing"
        case .ready: return "Ready"
        }
    }
}

// MARK: - Email Settings

enum EmailPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case always = "always"
    case ask = "ask"
    case never = "never"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .always: return "Always prepare email"
        case .ask: return "Ask before sending"
        case .never: return "Never send automatically"
        }
    }
}

enum EmailContent: String, Codable, CaseIterable, Identifiable, Sendable {
    case summaryOnly = "summary"
    case fullTranscript = "transcript"
    case both = "both"
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .summaryOnly: return "Summary only"
        case .fullTranscript: return "Full transcript"
        case .both: return "Summary and transcript"
        }
    }
}

enum SummaryLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short = "short"
    case detailed = "detailed"
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .short: return "Short"
        case .detailed: return "Detailed"
        }
    }
}

// MARK: - Provider IDs

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case luxasr = "luxasr"
    case openai = "openai"
    case elevenlabs = "elevenlabs"
    case apple = "apple"
    
    var displayName: String {
        switch self {
        case .luxasr: return "LuxASR (University of Luxembourg)"
        case .openai: return "OpenAI"
        case .elevenlabs: return "ElevenLabs Scribe"
        case .apple: return "Apple Speech (On-Device)"
        }
    }
    
    var sendsAudioOffDevice: Bool {
        switch self {
        case .apple: return false
        default: return true
        }
    }
    
    var country: String {
        switch self {
        case .luxasr: return "Luxembourg / EU"
        case .openai: return "United States"
        case .elevenlabs: return "United States"
        case .apple: return "On-Device"
        }
    }
}

enum StructuredSectionType: String, Codable, Sendable {
    case summary
    case keyIdeas
    case decisions
    case actionItems
    case questions
    case risks
    case nextSteps
    case people
    case dates
    case numbers
    case emailDraft
    case brainstorm
}
