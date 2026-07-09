import Foundation
import SwiftData

enum ReprocessError: LocalizedError {
    case audioMissing
    case transcriptMissing
    
    var errorDescription: String? {
        switch self {
        case .audioMissing:
            return "Audio file no longer available. Cannot transcribe again."
        case .transcriptMissing:
            return "No transcript available to re-summarize."
        }
    }
}

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
        clearTranscriptionResults(note)
        note.status = NoteStatus.processing.rawValue
        note.errorMessage = nil
        
        onStageChange(.transcribing)
        let request = TranscriptionRequest(
            audioURL: audioURL,
            language: note.appLanguage,
            enableDiarization: true,
            prompt: settingsService.transcriptionPrompt()
        )
        let initialResult = try await transcriptionService.transcribe(request)
        
        onStageChange(.checkingQuality)
        let finalTranscript = try await qualityPipeline.process(
            initialResult: initialResult,
            audioURL: audioURL,
            expectedLanguage: note.appLanguage,
            prompt: settingsService.transcriptionPrompt()
        )
        
        applyTranscript(finalTranscript, to: note)
        
        try await generateSummary(for: note, transcript: finalTranscript.fullText, onStageChange: onStageChange)
        
        if settingsService.deleteAudioAfterTranscription {
            storageService.deleteAudio(for: note.id)
            note.audioDeletedAt = .now
        }
        
        note.status = NoteStatus.ready.rawValue
        note.processingStage = ProcessingStage.ready.rawValue
        note.updatedAt = .now
        onStageChange(.ready)
    }
    
    func transcribeAgain(
        note: Note,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        let audioURL = storageService.audioURL(for: note.id)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ReprocessError.audioMissing
        }
        
        onStageChange(.savingAudio)
        try await execute(note: note, audioURL: audioURL, onStageChange: onStageChange)
    }
    
    func resummarize(
        note: Note,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        let transcript = note.displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw ReprocessError.transcriptMissing
        }
        
        note.status = NoteStatus.processing.rawValue
        note.errorMessage = nil
        clearSummaryResults(note)
        
        try await generateSummary(for: note, transcript: transcript, onStageChange: onStageChange)
        
        note.status = NoteStatus.ready.rawValue
        note.processingStage = ProcessingStage.ready.rawValue
        note.updatedAt = .now
        onStageChange(.ready)
    }
    
    private func applyTranscript(_ finalTranscript: FinalTranscript, to note: Note) {
        note.rawTranscript = finalTranscript.fullText
        note.primaryProvider = finalTranscript.primaryProvider
        note.detectedLanguage = note.language
        note.qualityReportJSON = try? JSONEncoder().encode(finalTranscript.qualityReport)
        note.segments = finalTranscript.segments.map { TranscriptSegmentModel(from: $0, note: note) }
    }
    
    private func generateSummary(
        for note: Note,
        transcript: String,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        if note.noteOutputType == .rawTranscript {
            note.summaryShort = nil
            note.summaryDetailed = nil
            note.structuredOutputJSON = nil
            note.structuredSections = []
            return
        }
        
        onStageChange(.summarizing)
        let structured = try await summaryService.generate(
            transcript: transcript,
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
    
    private func clearTranscriptionResults(_ note: Note) {
        note.segments.removeAll()
        note.structuredSections.removeAll()
        note.rawTranscript = nil
        note.correctedTranscript = nil
        note.primaryProvider = nil
        note.detectedLanguage = nil
        note.qualityReportJSON = nil
        clearSummaryResults(note)
    }
    
    private func clearSummaryResults(_ note: Note) {
        note.summaryShort = nil
        note.summaryDetailed = nil
        note.structuredOutputJSON = nil
        note.structuredSections.removeAll()
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
