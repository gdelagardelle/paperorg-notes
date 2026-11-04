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
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ waiting: Bool) -> Void)? = nil,
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
                audioURL: audioURL,
                onProgress: onProgress
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
                prompt: settingsService.transcriptionPrompt(),
                skipMixedLanguageDetection: note.hasMultipleRecordingLanguages
            )
            let trimmedTranscript = finalTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedTranscript.count >= 3 else {
                throw TranscriptionError.emptyResult
            }
            debugEvents.append("Overall confidence: \(String(format: "%.2f", finalTranscript.qualityReport.overallConfidence))")
            debugEvents.append("Low-confidence segments: \(finalTranscript.qualityReport.lowConfidenceSegmentIds.count)")

            // Keep the transcript even when the summary is refused, and leave
            // any earlier summary in place until a new one actually arrives.
            replaceStoredTranscript(finalTranscript, on: note, language: resolvedLanguage)
            try save(note)

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
            replaceSummary(on: note, summary: summary)

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
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ waiting: Bool) -> Void)? = nil,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws {
        let audioURL = storageService.audioURL(for: note.id)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ReprocessError.audioMissing
        }
        
        note.processingStage = ProcessingStage.savingAudio.rawValue
        onStageChange(.savingAudio)
        try save(note)
        try await execute(
            note: note,
            audioURL: audioURL,
            onProgress: onProgress,
            onStageChange: onStageChange
        )
    }
    
    func resummarize(
        note: Note,
        length: SummaryLength? = nil,
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
            let summary = try await generateSummary(for: note, transcript: transcript, language: note.summaryLanguage, length: length) { stage in
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
        audioURL: URL,
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ waiting: Bool) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        let noteLanguage = note.appLanguage
        let segments = note.recordingLanguageSegments
        let measuredDuration = await AudioTrimService.assetDuration(of: audioURL)
        let totalDuration = max(note.durationSeconds, measuredDuration)

        let planned: [LanguageAudioSlice]
        if TranscriptionLanguagePlanner.shouldTranscribeInSlices(
            noteLanguage: noteLanguage,
            segments: segments
        ) {
            planned = TranscriptionLanguagePlanner.recordingSlices(
                noteLanguage: noteLanguage,
                segments: segments,
                totalDuration: totalDuration
            )
            guard !planned.isEmpty else {
                throw TranscriptionError.providerError(
                    "Recording language switches were too close together. Record a bit longer in each language."
                )
            }
        } else if LongRecordingTranscription.takesLonger(totalDuration)
                    || AudioTrimService.fileByteCount(of: audioURL) > LongRecordingTranscription.maxUploadBytes {
            let span = totalDuration > 0 ? totalDuration : measuredDuration
            guard span > 0 else {
                throw TranscriptionError.providerError(
                    "This recording is too large to send in one piece, and its length could not be read."
                )
            }
            planned = [
                LanguageAudioSlice(language: noteLanguage, startTime: 0, endTime: span)
            ]
        } else {
            return try await transcribeSingle(
                noteLanguage: noteLanguage,
                audioURL: audioURL,
                explicitLanguage: noteLanguage,
                recordingSegment: nil
            )
        }

        var pending = planned.flatMap { LongRecordingTranscription.chunks(of: $0) }
        if pending.count == 1,
           pending[0].startTime <= 0.05,
           pending[0].endTime >= totalDuration - 0.5,
           AudioTrimService.fileByteCount(of: audioURL) <= LongRecordingTranscription.maxUploadBytes {
            return try await transcribeSingle(
                noteLanguage: pending[0].language,
                audioURL: audioURL,
                explicitLanguage: pending[0].language,
                recordingSegment: nil
            )
        }

        var sliceResults: [(slice: LanguageAudioSlice, result: TranscriptionResult)] = []
        var index = 0
        var completed = 0
        let estimate = max(1, Int((totalDuration / LongRecordingTranscription.chunkDuration).rounded(.up)))
        while !pending.isEmpty {
            let chunk = pending.removeFirst()
            let sliceURL = try await AudioTrimService.trim(
                sourceURL: audioURL,
                start: chunk.startTime,
                end: chunk.endTime
            )
            defer { try? FileManager.default.removeItem(at: sliceURL) }

            if AudioTrimService.fileByteCount(of: sliceURL) > LongRecordingTranscription.maxUploadBytes,
               chunk.duration > 20 {
                let mid = chunk.startTime + (chunk.duration / 2)
                pending.insert(
                    LanguageAudioSlice(language: chunk.language, startTime: mid, endTime: chunk.endTime),
                    at: 0
                )
                pending.insert(
                    LanguageAudioSlice(language: chunk.language, startTime: chunk.startTime, endTime: mid),
                    at: 0
                )
                continue
            }

            let total = max(estimate, completed + pending.count + 1)
            onProgress?(completed, total, false)
            let result = try await transcribeAllowingRateLimit(
                noteLanguage: chunk.language,
                audioURL: sliceURL,
                explicitLanguage: chunk.language,
                recordingSegment: RecordingSegmentIdentity(
                    sessionID: note.id,
                    index: index,
                    startSeconds: chunk.startTime
                ),
                onWait: {
                    onProgress?(completed, total, true)
                }
            )
            index += 1
            completed += 1
            onProgress?(completed, max(estimate, completed), false)
            sliceResults.append((chunk, result))
        }

        guard let merged = TranscriptionLanguagePlanner.mergeTranscriptionResults(sliceResults),
              !merged.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return merged
    }

    /// A long note sends several requests. The server allows a short burst,
    /// then asks the client to wait. Waiting here keeps the same note going.
    private func transcribeAllowingRateLimit(
        noteLanguage: AppLanguage,
        audioURL: URL,
        explicitLanguage: AppLanguage,
        recordingSegment: RecordingSegmentIdentity?,
        onWait: (@MainActor () -> Void)? = nil
    ) async throws -> TranscriptionResult {
        for attempt in 0..<12 {
            do {
                return try await transcribeSingle(
                    noteLanguage: noteLanguage,
                    audioURL: audioURL,
                    explicitLanguage: explicitLanguage,
                    recordingSegment: recordingSegment
                )
            } catch let error as ProBackendError where error.isTranscriptionRateLimit {
                if attempt == 11 { throw error }
                for _ in 0..<12 {
                    onWait?()
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                }
            }
        }
        throw ProBackendError.transcriptionRateLimited
    }

    private func transcribeSingle(
        noteLanguage: AppLanguage,
        audioURL: URL,
        explicitLanguage: AppLanguage,
        recordingSegment: RecordingSegmentIdentity?
    ) async throws -> TranscriptionResult {
        let requestLanguage = TranscriptionLanguagePlanner.requestLanguage(for: explicitLanguage)
        let request = TranscriptionRequest(
            audioURL: audioURL,
            language: requestLanguage,
            enableDiarization: false,
            prompt: settingsService.transcriptionPrompt(),
            fallbackLanguage: settingsService.defaultLanguage,
            recordingSegment: recordingSegment
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
                fallbackLanguage: settingsService.defaultLanguage,
                recordingSegment: recordingSegment
            )
            if let luxResult = try? await transcriptionService.transcribe(luxRequest),
               !luxResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = luxResult
            }
        }

        return result
    }

    private func replaceStoredTranscript(_ finalTranscript: FinalTranscript, on note: Note, language: AppLanguage) {
        if let context = note.modelContext {
            for segment in note.segments {
                context.delete(segment)
            }
        }
        note.segments.removeAll()
        note.correctedTranscript = nil
        applyTranscript(finalTranscript, to: note, language: language)
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
        length: SummaryLength? = nil,
        onStageChange: @escaping (ProcessingStage) -> Void
    ) async throws -> SummaryGeneration {
        if note.noteOutputType == .rawTranscript {
            return .notRequested
        }
        
        onStageChange(.summarizing)
        let spokenLanguage = TranscriptionLanguagePlanner.summaryLanguage(
            resolvedLanguage: language,
            noteLanguage: note.appLanguage,
            fallback: settingsService.defaultLanguage,
            hasMultipleRecordingLanguages: note.hasMultipleRecordingLanguages
        )
        let writeLanguage = settingsService.summaryWriteLanguage(for: note.id).appLanguage ?? spokenLanguage
        let languageName = SummaryWriteLanguage.requestLanguageName(output: writeLanguage, spoken: spokenLanguage)
        let translating = !writeLanguage.isAutoDetect && writeLanguage != spokenLanguage
        return try await summaryService.generate(
            transcript: transcript,
            outputType: note.noteOutputType,
            language: writeLanguage,
            languageName: languageName,
            length: length,
            translating: translating
        )
    }

    private func replaceSummary(on note: Note, summary: SummaryGeneration) {
        clearSummaryResults(note)
        guard let structured = summary.output else { return }
        let enriched = OfficeWorkflow.enrich(
            structured,
            transcript: note.displayTranscript,
            segments: note.segments,
            teammates: settingsService.officeRoster,
            defaultOwner: settingsService.owner(forProject: note.projectName)
        )
        note.summaryShort = enriched.shortSummary
        note.summaryDetailed = enriched.detailedSummary
        note.structuredOutputJSON = try? JSONEncoder().encode(enriched)
        
        if note.title == "Untitled Recording", let title = enriched.title, !title.isEmpty {
            note.title = title
        }
        note.structuredSections = buildSections(from: enriched, note: note)
    }
    
    private func clearSummaryResults(_ note: Note) {
        deleteSections(of: note)
        note.summaryShort = nil
        note.summaryDetailed = nil
        note.structuredOutputJSON = nil
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
            return "Transcription stopped. Open the note and tap Transcribe now to continue."
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

enum SessionMerge {
    /// Splits one saved recording into 3-hour parts when the session is longer.
    /// A shorter recording is returned unchanged.
    @MainActor
    static func split(
        _ note: Note,
        storage: StorageService,
        settings: SettingsService,
        context: ModelContext
    ) async -> [Note] {
        let duration = note.durationSeconds
        let boundaries = MergeableSession.parts(for: duration)
        guard boundaries.count > 1 else { return [note] }

        let source = storage.audioURL(for: note.id)
        var temps: [URL] = []
        var installed: [URL] = []
        do {
            for boundary in boundaries {
                let url = try await AudioTrimService.trim(
                    sourceURL: source,
                    start: boundary.start,
                    end: boundary.end
                )
                temps.append(url)
            }
            guard temps.count == boundaries.count else { throw AudioTrimError.exportFailed }

            let baseTitle = MergeableSession.titleWithoutPartSuffix(note.title)
            var partIDs = [note.id]
            for index in 1..<boundaries.count {
                let id = UUID()
                let destination = storage.audioURL(for: id)
                try storage.replaceAudio(at: destination, with: temps[index])
                installed.append(destination)
                partIDs.append(id)
            }
            try storage.replaceAudio(at: source, with: temps[0])

            note.durationSeconds = boundaries[0].end - boundaries[0].start
            note.title = MergeableSession.partTitle(baseTitle, index: 0, count: boundaries.count)
            note.recordingLanguageSegments = []
            note.status = NoteStatus.awaitingTranscription.rawValue

            var notes = [note]
            for index in 1..<boundaries.count {
                let id = partIDs[index]
                let part = Note(
                    id: id,
                    title: MergeableSession.partTitle(baseTitle, index: index, count: boundaries.count),
                    audioFileName: "\(id.uuidString).m4a",
                    language: note.appLanguage,
                    outputType: note.noteOutputType,
                    status: .awaitingTranscription
                )
                part.durationSeconds = boundaries[index].end - boundaries[index].start
                context.insert(part)
                notes.append(part)
            }
            settings.assignMergeGroup(notes.map(\.id))
            try context.save()
            return notes
        } catch {
            for url in temps + installed {
                try? FileManager.default.removeItem(at: url)
            }
            return [note]
        }
    }

    @MainActor
    static func merge(
        _ notes: [Note],
        storage: StorageService,
        settings: SettingsService,
        context: ModelContext
    ) async throws {
        guard notes.count > 1 else { return }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-\(UUID().uuidString).m4a")
        try await AudioTrimService.join(
            urls: notes.map { storage.audioURL(for: $0.id) },
            into: output
        )
        let primary = notes[0]
        try storage.replaceAudio(at: storage.audioURL(for: primary.id), with: output)
        primary.durationSeconds = notes.reduce(0) { $0 + $1.durationSeconds }
        primary.title = MergeableSession.titleWithoutPartSuffix(primary.title)
        primary.recordingLanguageSegments = []
        primary.updatedAt = .now

        let transcripts = notes.map {
            $0.displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let kept = transcripts.filter { !$0.isEmpty }
        clearGeneratedText(on: primary, context: context)
        if kept.count == notes.count {
            primary.rawTranscript = kept.joined(separator: "\n\n")
            primary.status = NoteStatus.ready.rawValue
        } else {
            primary.rawTranscript = kept.isEmpty ? nil : kept.joined(separator: "\n\n")
            primary.status = NoteStatus.awaitingTranscription.rawValue
        }

        settings.clearMergeGroup(containing: primary.id)
        for extra in notes.dropFirst() {
            storage.deleteAudio(for: extra.id)
            for segment in extra.segments {
                context.delete(segment)
            }
            for section in extra.structuredSections {
                context.delete(section)
            }
            context.delete(extra)
        }
        try context.save()
    }

    @MainActor
    private static func clearGeneratedText(on note: Note, context: ModelContext) {
        for segment in note.segments {
            context.delete(segment)
        }
        note.segments.removeAll()
        for section in note.structuredSections {
            context.delete(section)
        }
        note.structuredSections.removeAll()
        note.rawTranscript = nil
        note.correctedTranscript = nil
        note.summaryShort = nil
        note.summaryDetailed = nil
        note.structuredOutputJSON = nil
        note.qualityReportJSON = nil
        note.errorMessage = nil
    }
}
