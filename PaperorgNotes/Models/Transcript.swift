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
    let fallbackLanguage: AppLanguage
    let recordingSegment: RecordingSegmentIdentity?

    var autoDetect: Bool { language.isAutoDetect }

    init(
        audioURL: URL,
        language: AppLanguage,
        enableDiarization: Bool = true,
        prompt: String? = nil,
        segmentTimeRange: ClosedRange<Double>? = nil,
        fallbackLanguage: AppLanguage = .english,
        recordingSegment: RecordingSegmentIdentity? = nil
    ) {
        self.audioURL = audioURL
        self.language = language
        self.enableDiarization = enableDiarization
        self.prompt = prompt
        self.segmentTimeRange = segmentTimeRange
        self.fallbackLanguage = fallbackLanguage
        self.recordingSegment = recordingSegment
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

enum TaskWorkflowStatus: String, Codable, CaseIterable, Sendable {
    case open
    case handedOff
    case waiting
    case done

    var title: String {
        switch self {
        case .open: "Open"
        case .handedOff: "Handed off"
        case .waiting: "Waiting"
        case .done: "Done"
        }
    }
}

enum TaskHandoffMail: String, Codable, Sendable {
    case none
    case mailOpened
}

struct ActionItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String
    var assignee: String?
    var dueDate: String?
    var dueAt: Date?
    var isCompleted: Bool
    var status: TaskWorkflowStatus
    var handoffMail: TaskHandoffMail
    var returnNote: String?
    var heardExcerpt: String?
    var splitFrom: UUID?

    init(
        id: UUID = UUID(),
        text: String,
        assignee: String? = nil,
        dueDate: String? = nil,
        dueAt: Date? = nil,
        isCompleted: Bool = false,
        status: TaskWorkflowStatus = .open,
        handoffMail: TaskHandoffMail = .none,
        returnNote: String? = nil,
        heardExcerpt: String? = nil,
        splitFrom: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.assignee = assignee
        self.dueDate = dueDate
        self.dueAt = dueAt ?? TaskDueDate.parse(dueDate)
        self.isCompleted = isCompleted || status == .done
        self.status = self.isCompleted ? .done : status
        self.handoffMail = handoffMail
        self.returnNote = returnNote
        self.heardExcerpt = heardExcerpt
        self.splitFrom = splitFrom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt) ?? TaskDueDate.parse(dueDate)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        let decodedStatus = try container.decodeIfPresent(TaskWorkflowStatus.self, forKey: .status)
        status = isCompleted ? .done : (decodedStatus ?? .open)
        handoffMail = try container.decodeIfPresent(TaskHandoffMail.self, forKey: .handoffMail) ?? .none
        returnNote = try container.decodeIfPresent(String.self, forKey: .returnNote)
        heardExcerpt = try container.decodeIfPresent(String.self, forKey: .heardExcerpt)
        splitFrom = try container.decodeIfPresent(UUID.self, forKey: .splitFrom)
        if status == .done {
            isCompleted = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(assignee, forKey: .assignee)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(status, forKey: .status)
        try container.encode(handoffMail, forKey: .handoffMail)
        try container.encodeIfPresent(returnNote, forKey: .returnNote)
        try container.encodeIfPresent(heardExcerpt, forKey: .heardExcerpt)
        try container.encodeIfPresent(splitFrom, forKey: .splitFrom)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, assignee, dueDate, dueAt, isCompleted, status, handoffMail, returnNote, heardExcerpt, splitFrom
    }
}

enum TaskDueDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.lowercased() != "[not mentioned]" else { return nil }

        let lowered = text.lowercased()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        if lowered == "today" || lowered == "aujourd'hui" || lowered == "haut" || lowered == "heute" {
            return start
        }
        if lowered == "tomorrow" || lowered == "demain" || lowered == "muer" || lowered == "morgen" {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let index = weekdays.firstIndex(of: lowered) {
            let weekday = index + 1
            var components = DateComponents()
            components.weekday = weekday
            return calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "dd/MM/yyyy", "dd.MM.yyyy", "d MMM yyyy", "MMM d"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    static func isTodayOrOverdue(_ date: Date?) -> Bool {
        guard let date else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: .now)
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
            if lang.isAutoDetect {
                return "No transcription provider available for automatic language detection."
            }
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
