import Foundation
import SwiftData

@MainActor
final class ProcessRecordingUseCase {
    private let transcriptionService: TranscriptionService
    private let summaryService: SummaryService
    private let storageService: StorageService
    private let qualityPipeline: QualityPipeline
    private let settingsService: SettingsService
    
    init(
        transcriptionService: TranscriptionService,
        summaryService: SummaryService,
        storageService: StorageService,
        qualityPipeline: QualityPipeline,
        settingsService: SettingsService
    ) {
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
        self.storageService = storageService
        self.qualityPipeline = qualityPipeline
        self.settingsService = settingsService
    }
    
    func execute(
        note: Note,
        audioURL: URL,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        note.status = NoteStatus.processing.rawValue
        
        // Transcribe
        onStageChange(.transcribing)
        let request = TranscriptionRequest(
            audioURL: audioURL,
            language: note.appLanguage,
            enableDiarization: true
        )
        let initialResult = try await transcriptionService.transcribe(request)
        
        // Quality check
        onStageChange(.checkingQuality)
        let finalTranscript = try await qualityPipeline.process(
            initialResult: initialResult,
            audioURL: audioURL,
            expectedLanguage: note.appLanguage
        )
        
        note.rawTranscript = finalTranscript.fullText
        note.primaryProvider = finalTranscript.primaryProvider
        note.detectedLanguage = note.language
        note.qualityReportJSON = try? JSONEncoder().encode(finalTranscript.qualityReport)
        
        note.segments = finalTranscript.segments.map { TranscriptSegmentModel(from: $0, note: note) }
        
        // Summarize
        if note.noteOutputType != .rawTranscript {
            onStageChange(.summarizing)
            let structured = try await summaryService.generate(
                transcript: finalTranscript.fullText,
                outputType: note.noteOutputType,
                language: note.appLanguage
            )
            
            note.summaryShort = structured.shortSummary
            note.summaryDetailed = structured.detailedSummary
            note.structuredOutputJSON = try? JSONEncoder().encode(structured)
            
            if note.title == "Untitled Recording", let title = structured.title, !title.isEmpty {
                note.title = title
            }
            
            note.structuredSections = buildSections(from: structured, note: note)
        }
        
        // Audio retention
        if settingsService.deleteAudioAfterTranscription {
            storageService.deleteAudio(for: note.id)
            note.audioDeletedAt = .now
        }
        
        note.status = NoteStatus.ready.rawValue
        note.processingStage = ProcessingStage.ready.rawValue
        note.updatedAt = .now
        onStageChange(.ready)
    }
    
    private func buildSections(from output: StructuredOutput, note: Note) -> [StructuredSectionModel] {
        var sections: [StructuredSectionModel] = []
        var order = 0
        
        if !output.keyIdeas.isEmpty {
            sections.append(StructuredSectionModel(
                type: .keyIdeas, title: "Key Ideas", content: "",
                items: output.keyIdeas, order: order, note: note
            ))
            order += 1
        }
        
        if !output.decisions.isEmpty {
            sections.append(StructuredSectionModel(
                type: .decisions, title: "Decisions", content: "",
                items: output.decisions, order: order, note: note
            ))
            order += 1
        }
        
        if !output.actionItems.isEmpty {
            sections.append(StructuredSectionModel(
                type: .actionItems, title: "Action Items", content: "",
                items: output.actionItems.map(\.text), order: order, note: note
            ))
            order += 1
        }
        
        if !output.openQuestions.isEmpty {
            sections.append(StructuredSectionModel(
                type: .questions, title: "Open Questions", content: "",
                items: output.openQuestions, order: order, note: note
            ))
        }
        
        return sections
    }
}
