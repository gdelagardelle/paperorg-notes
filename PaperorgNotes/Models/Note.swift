import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var durationSeconds: Double
    var audioFileName: String
    var audioDeletedAt: Date?
    var language: String
    var detectedLanguage: String?
    var languageConfidence: Double?
    var outputType: String
    var status: String
    var processingStage: String?
    var isFavorite: Bool
    var projectName: String?
    var rawTranscript: String?
    var correctedTranscript: String?
    var summaryShort: String?
    var summaryDetailed: String?
    var structuredOutputJSON: Data?
    var qualityReportJSON: Data?
    var primaryProvider: String?
    var tags: [String]
    var errorMessage: String?
    var processingDebug: String?
    
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegmentModel.note)
    var segments: [TranscriptSegmentModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \StructuredSectionModel.note)
    var structuredSections: [StructuredSectionModel] = []
    
    init(
        id: UUID = UUID(),
        title: String = "Untitled Recording",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        durationSeconds: Double = 0,
        audioFileName: String,
        language: AppLanguage,
        outputType: OutputType,
        status: NoteStatus = .draft
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.language = language.rawValue
        self.outputType = outputType.rawValue
        self.status = status.rawValue
        self.isFavorite = false
        self.tags = []
    }
    
    var appLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }
    
    var noteStatus: NoteStatus {
        NoteStatus(rawValue: status) ?? .draft
    }
    
    var noteOutputType: OutputType {
        OutputType(rawValue: outputType) ?? .meetingNotes
    }
    
    var displayTranscript: String {
        if let corrected = correctedTranscript, !corrected.isEmpty {
            return corrected
        }
        if !segments.isEmpty {
            return segments
                .sorted { $0.segmentIndex < $1.segmentIndex }
                .map(\.text)
                .joined(separator: " ")
        }
        if let cleaned = TranscriptTextFormatter.readableText(from: rawTranscript) {
            return cleaned
        }
        return rawTranscript ?? ""
    }
    
    var displaySummaryShort: String {
        if let summary = summaryShort,
           !summary.isEmpty,
           !TranscriptTextFormatter.isRawJSON(summary) {
            return summary
        }
        return displayTranscript
    }
    
    var structuredOutput: StructuredOutput? {
        guard let data = structuredOutputJSON else { return nil }
        return try? JSONDecoder().decode(StructuredOutput.self, from: data)
    }
    
    var qualityReport: QualityReport? {
        guard let data = qualityReportJSON else { return nil }
        return try? JSONDecoder().decode(QualityReport.self, from: data)
    }
}

@Model
final class TranscriptSegmentModel {
    @Attribute(.unique) var id: UUID
    var segmentIndex: Int
    var text: String
    var startTime: Double
    var endTime: Double
    var confidence: Double
    var speakerLabel: String?
    var isUnclear: Bool
    var isUserCorrected: Bool
    var originalText: String?
    var providerId: String?
    
    var note: Note?
    
    init(from dto: TranscriptSegmentDTO, note: Note? = nil) {
        self.id = dto.id
        self.segmentIndex = dto.index
        self.text = dto.text
        self.startTime = dto.startTime
        self.endTime = dto.endTime
        self.confidence = dto.confidence
        self.speakerLabel = dto.speakerLabel
        self.isUnclear = dto.isUnclear
        self.isUserCorrected = false
        self.originalText = nil
        self.providerId = dto.providerId
        self.note = note
    }
}

@Model
final class StructuredSectionModel {
    @Attribute(.unique) var id: UUID
    var type: String
    var title: String?
    var content: String
    var items: [String]
    var order: Int
    
    var note: Note?
    
    init(type: StructuredSectionType, title: String?, content: String, items: [String] = [], order: Int, note: Note? = nil) {
        self.id = UUID()
        self.type = type.rawValue
        self.title = title
        self.content = content
        self.items = items
        self.order = order
        self.note = note
    }
}
