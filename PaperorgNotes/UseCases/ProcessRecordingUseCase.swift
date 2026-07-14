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
        let startedAt = Date()
        var debugEvents = [
            "Started: \(ISO8601DateFormatter().string(from: startedAt))",
            "Language: \(note.appLanguage.displayName)",
            "Audio duration: \(String(format: "%.1f", note.durationSeconds)) seconds",
            "Audio bytes: \((try? Data(contentsOf: audioURL).count) ?? 0)",
            "Diarization: disabled"
        ]
        note.status = NoteStatus.processing.rawValue
        note.errorMessage = nil
        try save(note)
        func advance(_ stage: ProcessingStage) {
            note.processingStage = stage.rawValue
            debugEvents.append("Stage: \(stage.displayName) at +\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
            onStageChange(stage)
        }

        do {
            advance(.transcribing)
            storageService.prepareAudioForReading(noteId: note.id)
            let request = TranscriptionRequest(
                audioURL: audioURL,
                language: note.appLanguage,
                enableDiarization: false,
                prompt: settingsService.transcriptionPrompt()
            )
            let initialResult = try await transcriptionService.transcribe(request)
            debugEvents.append("Transcription provider: \(initialResult.providerId)")
            debugEvents.append("Transcription time: \(initialResult.processingTimeMs) ms")
            if let attemptLog = initialResult.metadata["attemptLog"] {
                debugEvents.append("Provider attempts: \(attemptLog)")
            }
            if let jobId = initialResult.metadata["jobId"] {
                debugEvents.append("LuxASR job ID: \(jobId)")
            }
            if let pollHistory = initialResult.metadata["pollHistory"] {
                debugEvents.append("LuxASR poll history: \(pollHistory)")
            }

            advance(.checkingQuality)
            let finalTranscript = try await qualityPipeline.process(
                initialResult: initialResult,
                audioURL: audioURL,
                expectedLanguage: note.appLanguage,
                prompt: settingsService.transcriptionPrompt()
            )
            debugEvents.append("Overall confidence: \(String(format: "%.2f", finalTranscript.qualityReport.overallConfidence))")
            debugEvents.append("Low-confidence segments: \(finalTranscript.qualityReport.lowConfidenceSegmentIds.count)")

            let summary = try await generateSummary(
                for: note,
                transcript: finalTranscript.fullText,
                onStageChange: advance
            )
            debugEvents.append(summary.usedFallback ? "Summary: fallback" : "Summary: generated")
            replaceResults(on: note, transcript: finalTranscript, summary: summary)

            if settingsService.deleteAudioAfterTranscription || !settingsService.keepAudioFiles {
                storageService.deleteAudio(for: note.id)
                note.audioDeletedAt = .now
            }

            note.status = NoteStatus.ready.rawValue
            note.processingStage = ProcessingStage.ready.rawValue
            note.updatedAt = .now
            advance(.ready)
            debugEvents.append("Completed in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
            note.processingDebug = debugEvents.joined(separator: "\n")
            try save(note)
        } catch {
            debugEvents.append("Failed at +\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
            debugEvents.append("Error: \(error.localizedDescription)")
            note.status = NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = safeErrorMessage(for: error)
            note.updatedAt = .now
            note.processingDebug = debugEvents.joined(separator: "\n")
            try? save(note)
            throw error
        }
    }
    
    func transcribeAgain(
        note: Note,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        let audioURL = storageService.audioURL(for: note.id)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ReprocessError.audioMissing
        }
        
        note.processingStage = ProcessingStage.savingAudio.rawValue
        onStageChange(.savingAudio)
        try save(note)
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
        note.processingStage = ProcessingStage.summarizing.rawValue
        try save(note)

        do {
            let summary = try await generateSummary(for: note, transcript: transcript) { stage in
                note.processingStage = stage.rawValue
                onStageChange(stage)
            }
            replaceSummary(on: note, summary: summary)
            note.status = NoteStatus.ready.rawValue
            note.processingStage = ProcessingStage.ready.rawValue
            note.updatedAt = .now
            onStageChange(.ready)
            try save(note)
        } catch {
            note.status = NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = safeErrorMessage(for: error)
            note.updatedAt = .now
            try? save(note)
            throw error
        }
    }
    
    private func replaceResults(on note: Note, transcript: FinalTranscript, summary: SummaryGeneration) {
        clearTranscriptionResults(note)
        applyTranscript(transcript, to: note)
        replaceSummary(on: note, summary: summary)
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
    ) async throws -> SummaryGeneration {
        if note.noteOutputType == .rawTranscript {
            return .notRequested
        }
        
        onStageChange(.summarizing)
        return try await summaryService.generate(
            transcript: transcript,
            outputType: note.noteOutputType,
            language: note.appLanguage
        )
    }

    private func replaceSummary(on note: Note, summary: SummaryGeneration) {
        clearSummaryResults(note)
        guard let structured = summary.output else { return }
        note.summaryShort = structured.shortSummary
        note.summaryDetailed = structured.detailedSummary
        note.structuredOutputJSON = try? JSONEncoder().encode(structured)
        
        if note.title == "Untitled Recording", let title = structured.title, !title.isEmpty {
            note.title = title
        }
        note.structuredSections = buildSections(from: structured, note: note)
    }
    
    private func clearTranscriptionResults(_ note: Note) {
        deleteChildren(of: note)
        note.segments.removeAll()
        note.rawTranscript = nil
        note.correctedTranscript = nil
        note.primaryProvider = nil
        note.detectedLanguage = nil
        note.qualityReportJSON = nil
        clearSummaryResults(note)
    }
    
    private func clearSummaryResults(_ note: Note) {
        deleteSections(of: note)
        note.summaryShort = nil
        note.summaryDetailed = nil
        note.structuredOutputJSON = nil
    }

    private func deleteChildren(of note: Note) {
        guard let context = note.modelContext else { return }
        for segment in note.segments {
            context.delete(segment)
        }
        deleteSections(of: note)
    }

    private func deleteSections(of note: Note) {
        guard let context = note.modelContext else { return }
        for section in note.structuredSections {
            context.delete(section)
        }
        note.structuredSections.removeAll()
    }

    private func save(_ note: Note) throws {
        guard let context = note.modelContext else { return }
        do {
            try context.save()
        } catch {
            throw RecordingError.saveFailed("Could not update the recording. Please try again.")
        }
    }

    private func safeErrorMessage(for error: Error) -> String {
        if let error = error as? ReprocessError {
            return error.localizedDescription
        }
        if let error = error as? TranscriptionError {
            return error.localizedDescription
        }
        if error is CancellationError {
            return "Processing was cancelled. Your previous transcript and summary were kept."
        }
        if error is DecodingError {
            return "Processing failed because the server returned an unexpected response. Open the note and tap Transcribe again."
        }
        return error.localizedDescription
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
