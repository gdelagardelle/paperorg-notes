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
    private let subscriptionService: SubscriptionService
    
    init(
        transcriptionService: TranscriptionService,
        summaryService: SummaryService,
        storageService: StorageService,
        qualityPipeline: QualityPipeline,
        settingsService: SettingsService,
        subscriptionService: SubscriptionService
    ) {
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
        self.storageService = storageService
        self.qualityPipeline = qualityPipeline
        self.settingsService = settingsService
        self.subscriptionService = subscriptionService
    }
    
    func execute(
        note: Note,
        audioURL: URL,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        let startedAt = Date()
        var debugEvents = [
            "Started: \(ISO8601DateFormatter().string(from: startedAt))",
            "Language: \(languageDebugLabel(for: note))",
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
            await subscriptionService.ensureServerProConfirmedBeforeProcessing()
            storageService.prepareAudioForReading(noteId: note.id)

            let measuredDuration = AudioTrimService.playableDuration(of: audioURL)
            if measuredDuration > 0 {
                note.durationSeconds = measuredDuration
            }
            debugEvents.append("Measured audio duration: \(String(format: "%.1f", note.durationSeconds)) seconds")

            let audioBytes = (try? Data(contentsOf: audioURL).count) ?? 0
            guard note.durationSeconds >= 0.5, audioBytes > 1024 else {
                throw TranscriptionError.providerError(
                    "Recording is too short or silent. Hold the mic closer and speak for at least a few seconds."
                )
            }

            let initialResult = try await transcribeRecording(
                note: note,
                audioURL: audioURL
            )
            let resolvedLanguage = initialResult.language
            note.detectedLanguage = resolvedLanguage.rawValue
            debugEvents.append("Detected language: \(resolvedLanguage.displayName)")
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
                expectedLanguage: resolvedLanguage,
                prompt: settingsService.transcriptionPrompt()
            )
            let trimmedTranscript = finalTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTranscript.count >= 3 else {
                throw TranscriptionError.emptyResult
            }
            debugEvents.append("Overall confidence: \(String(format: "%.2f", finalTranscript.qualityReport.overallConfidence))")
            debugEvents.append("Low-confidence segments: \(finalTranscript.qualityReport.lowConfidenceSegmentIds.count)")

            let summary = try await generateSummary(
                for: note,
                transcript: finalTranscript.fullText,
                language: resolvedLanguage,
                onStageChange: advance
            )
            debugEvents.append(summary.usedFallback ? "Summary: fallback" : "Summary: generated")
            if let output = summary.output {
                debugEvents.append("Summary short chars: \(output.shortSummary.count)")
            }
            replaceResults(on: note, transcript: finalTranscript, summary: summary, language: resolvedLanguage)

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
            let waitsForConnectivity = OfflineTranscriptionRecoveryPolicy.isConnectivityFailure(error)
            note.status = waitsForConnectivity
                ? NoteStatus.waitingForNetwork.rawValue
                : NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = waitsForConnectivity ? nil : safeErrorMessage(for: error)
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
            let summary = try await generateSummary(for: note, transcript: transcript, language: note.displayLanguage) { stage in
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
    
    private func transcribeRecording(
        note: Note,
        audioURL: URL
    ) async throws -> TranscriptionResult {
        let noteLanguage = note.appLanguage
        let segments = note.recordingLanguageSegments

        if TranscriptionLanguagePlanner.shouldTranscribeInSlices(
            noteLanguage: noteLanguage,
            segments: segments
        ) {
            let slices = TranscriptionLanguagePlanner.recordingSlices(
                noteLanguage: noteLanguage,
                segments: segments,
                totalDuration: note.durationSeconds
            )
            guard !slices.isEmpty else {
                throw TranscriptionError.providerError(
                    "Recording language switches were too close together. Record a bit longer in each language."
                )
            }

            var sliceResults: [(slice: LanguageAudioSlice, result: TranscriptionResult)] = []
            sliceResults.reserveCapacity(slices.count)

            for slice in slices {
                let sliceURL = try await AudioTrimService.trim(
                    sourceURL: audioURL,
                    start: slice.startTime,
                    end: slice.endTime
                )
                defer { try? FileManager.default.removeItem(at: sliceURL) }

                let result = try await transcribeSingle(
                    noteLanguage: slice.language,
                    audioURL: sliceURL,
                    explicitLanguage: slice.language
                )
                sliceResults.append((slice, result))
            }

            guard let merged = TranscriptionLanguagePlanner.mergeTranscriptionResults(sliceResults),
                  !merged.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionError.emptyResult
            }
            return merged
        }

        return try await transcribeSingle(
            noteLanguage: noteLanguage,
            audioURL: audioURL,
            explicitLanguage: noteLanguage
        )
    }

    private func transcribeSingle(
        noteLanguage: AppLanguage,
        audioURL: URL,
        explicitLanguage: AppLanguage
    ) async throws -> TranscriptionResult {
        let requestLanguage = TranscriptionLanguagePlanner.requestLanguage(for: explicitLanguage)
        let request = TranscriptionRequest(
            audioURL: audioURL,
            language: requestLanguage,
            enableDiarization: false,
            prompt: settingsService.transcriptionPrompt(),
            fallbackLanguage: settingsService.defaultLanguage
        )
        var result = try await transcriptionService.transcribe(request)

        if TranscriptionLanguagePlanner.shouldUpgradeAutoDetectToLuxASR(
            wasAutoDetect: noteLanguage.isAutoDetect,
            resolvedLanguage: result.language,
            providerId: result.providerId,
            luxasrEnabled: settingsService.luxasrEnabled
        ) {
            let luxRequest = TranscriptionRequest(
                audioURL: audioURL,
                language: .luxembourgish,
                enableDiarization: false,
                prompt: settingsService.transcriptionPrompt(),
                fallbackLanguage: settingsService.defaultLanguage
            )
            if let luxResult = try? await transcriptionService.transcribe(luxRequest),
               !luxResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = luxResult
            }
        }

        return result
    }

    private func replaceResults(on note: Note, transcript: FinalTranscript, summary: SummaryGeneration, language: AppLanguage) {
        clearTranscriptionResults(note)
        applyTranscript(transcript, to: note, language: language)
        replaceSummary(on: note, summary: summary)
    }

    private func applyTranscript(_ finalTranscript: FinalTranscript, to note: Note, language: AppLanguage) {
        note.rawTranscript = finalTranscript.fullText
        note.primaryProvider = finalTranscript.primaryProvider
        note.detectedLanguage = language.rawValue
        note.qualityReportJSON = try? JSONEncoder().encode(finalTranscript.qualityReport)
        note.segments = finalTranscript.segments.map { TranscriptSegmentModel(from: $0, note: note) }
    }
    
    private func generateSummary(
        for note: Note,
        transcript: String,
        language: AppLanguage,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws -> SummaryGeneration {
        if note.noteOutputType == .rawTranscript {
            return .notRequested
        }
        
        onStageChange(.summarizing)
        let summaryLanguage = TranscriptionLanguagePlanner.summaryLanguage(
            resolvedLanguage: language,
            noteLanguage: note.appLanguage,
            fallback: settingsService.defaultLanguage,
            hasMultipleRecordingLanguages: note.hasMultipleRecordingLanguages
        )
        return try await summaryService.generate(
            transcript: transcript,
            outputType: note.noteOutputType,
            language: summaryLanguage
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

    private func languageDebugLabel(for note: Note) -> String {
        if note.hasMultipleRecordingLanguages {
            return note.displayLanguageLabel
        }
        if note.appLanguage.isAutoDetect {
            return "Auto-detect"
        }
        return note.appLanguage.displayName
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
