import Foundation

struct TranscriptSegmentDTO: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let index: Int
    var text: String
    let startTime: Double
    let endTime: Double
    let confidence: Double
    let speakerLabel: String?
    var isUnclear: Bool
    let providerId: String?
    
    init(
        id: UUID = UUID(),
        index: Int,
        text: String,
        startTime: Double,
        endTime: Double,
        confidence: Double,
        speakerLabel: String? = nil,
        isUnclear: Bool = false,
        providerId: String? = nil
    ) {
        self.id = id
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerLabel = speakerLabel
        self.isUnclear = isUnclear
        self.providerId = providerId
    }
}

struct TranscriptionRequest: Sendable {
    let audioURL: URL
    let language: AppLanguage
    let enableDiarization: Bool
    let prompt: String?
    let segmentTimeRange: ClosedRange<Double>?
    
    init(
        audioURL: URL,
        language: AppLanguage,
        enableDiarization: Bool = true,
        prompt: String? = nil,
        segmentTimeRange: ClosedRange<Double>? = nil
    ) {
        self.audioURL = audioURL
        self.language = language
        self.enableDiarization = enableDiarization
        self.prompt = prompt
        self.segmentTimeRange = segmentTimeRange
    }
}

struct TranscriptionResult: Codable, Sendable {
    let providerId: String
    let language: AppLanguage
    let segments: [TranscriptSegmentDTO]
    let fullText: String
    let averageConfidence: Double
    let processingTimeMs: Int
    let metadata: [String: String]
    
    var lowConfidenceSegments: [TranscriptSegmentDTO] {
        segments.filter { $0.confidence < 0.6 || $0.isUnclear }
    }
}

struct ActionItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let text: String
    let assignee: String?
    let dueDate: String?
    var isCompleted: Bool
    
    init(id: UUID = UUID(), text: String, assignee: String? = nil, dueDate: String? = nil, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.assignee = assignee
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}

struct StructuredOutput: Codable, Sendable {
    let outputType: OutputType
    let title: String?
    let shortSummary: String
    let detailedSummary: String
    let keyIdeas: [String]
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    let risks: [String]
    let nextSteps: [String]
    let peopleMentioned: [String]
    let datesMentioned: [String]
    let importantNumbers: [String]
    let followUpEmailDraft: String?
    let generatedAt: Date
    
    static func empty(for type: OutputType) -> StructuredOutput {
        StructuredOutput(
            outputType: type,
            title: nil,
            shortSummary: "",
            detailedSummary: "",
            keyIdeas: [],
            decisions: [],
            actionItems: [],
            openQuestions: [],
            risks: [],
            nextSteps: [],
            peopleMentioned: [],
            datesMentioned: [],
            importantNumbers: [],
            followUpEmailDraft: nil,
            generatedAt: .now
        )
    }
}

enum SummaryGeneration: Sendable {
    case generated(StructuredOutput)
    case fallback(StructuredOutput)
    case notRequested

    var output: StructuredOutput? {
        switch self {
        case .generated(let output), .fallback(let output):
            return output
        case .notRequested:
            return nil
        }
    }

    var usedFallback: Bool {
        if case .fallback = self {
            return true
        }
        return false
    }
}

struct SuspiciousPhrase: Codable, Sendable, Hashable {
    let segmentIndex: Int
    let reason: String
    let text: String
}

struct MixedLanguageSegment: Codable, Sendable, Hashable {
    let segmentIndex: Int
    let detectedLanguage: String
    let text: String
}

struct QualityReport: Codable, Sendable {
    let overallConfidence: Double
    let languageValidationPassed: Bool
    let detectedLanguage: AppLanguage
    let lowConfidenceSegmentIds: [UUID]
    let suspiciousPhrases: [SuspiciousPhrase]
    let mixedLanguageSegments: [MixedLanguageSegment]
    let providersUsed: [String]
    let retranscribedSegmentCount: Int
}

struct FinalTranscript: Sendable {
    let segments: [TranscriptSegmentDTO]
    let fullText: String
    let qualityReport: QualityReport
    let primaryProvider: String
}

struct EmailPayload: Sendable {
    let recipients: [String]
    let subject: String
    let body: String
    let htmlBody: String
    let audioURL: URL?
    let pdfURL: URL?
    let markdownURL: URL?
}

enum TranscriptionError: LocalizedError, Sendable {
    case noProviderAvailable(AppLanguage)
    case providerNotConsented(ProviderID)
    case missingAPIKey(ProviderID)
    case audioFileNotFound
    case networkError(String)
    case providerError(String)
    case emptyResult
    
    var errorDescription: String? {
        switch self {
        case .noProviderAvailable(let lang):
            return "No transcription provider available for \(lang.displayName)."
        case .providerNotConsented(let provider):
            return "Consent required before using \(provider.displayName)."
        case .missingAPIKey(let provider):
            return "API key missing for \(provider.displayName). Add it in Settings."
        case .audioFileNotFound:
            return "Audio file not found."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .providerError(let msg):
            return "Transcription failed: \(msg)"
        case .emptyResult:
            return "Transcription returned no text."
        }
    }
}

enum RecordingError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case setupFailed(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied."
        case .alreadyRecording: return "Already recording."
        case .notRecording: return "Not currently recording."
        case .setupFailed(let msg): return "Recording setup failed: \(msg)"
        case .saveFailed(let msg): return "Failed to save recording: \(msg)"
        }
    }
}
