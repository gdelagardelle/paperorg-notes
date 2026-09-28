import Foundation

struct LanguageAudioSlice: Sendable, Hashable {
    let language: AppLanguage
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }
}

/// Pure helpers for transcription language planning.
enum TranscriptionLanguagePlanner {
    static let minimumSliceDuration: TimeInterval = 0.5

    static func requestLanguage(for noteLanguage: AppLanguage) -> AppLanguage {
        noteLanguage.isAutoDetect ? .autoDetect : noteLanguage
    }

    /// After auto-detect resolves to Luxembourgish via OpenAI/ElevenLabs, retry with LuxASR.
    static func shouldUpgradeAutoDetectToLuxASR(
        wasAutoDetect: Bool,
        resolvedLanguage: AppLanguage,
        providerId: String,
        luxasrEnabled: Bool
    ) -> Bool {
        wasAutoDetect
            && resolvedLanguage == .luxembourgish
            && luxasrEnabled
            && providerId != ProviderID.luxasr.rawValue
    }

    static func summaryLanguage(
        resolvedLanguage: AppLanguage,
        noteLanguage: AppLanguage,
        fallback: AppLanguage,
        hasMultipleRecordingLanguages: Bool = false
    ) -> AppLanguage {
        if noteLanguage.isAutoDetect || hasMultipleRecordingLanguages {
            return resolvedLanguage.isAutoDetect ? fallback : resolvedLanguage
        }
        return resolvedLanguage.isAutoDetect ? fallback : resolvedLanguage
    }

    /// Build transcribable audio slices from note language boundaries.
    static func recordingSlices(
        noteLanguage: AppLanguage,
        segments: [RecordingLanguageSegment],
        totalDuration: TimeInterval,
        minimumSliceDuration: TimeInterval = minimumSliceDuration
    ) -> [LanguageAudioSlice] {
        guard !noteLanguage.isAutoDetect else { return [] }

        let sorted = segments
            .sorted { $0.startTime < $1.startTime }
            .compactMap { segment -> (AppLanguage, TimeInterval)? in
                guard let language = AppLanguage(rawValue: segment.languageCode),
                      !language.isAutoDetect else {
                    return nil
                }
                return (language, segment.startTime)
            }

        guard sorted.count > 1 else {
            let language = sorted.first?.0 ?? noteLanguage
            guard totalDuration >= minimumSliceDuration else { return [] }
            return [LanguageAudioSlice(language: language, startTime: 0, endTime: totalDuration)]
        }

        var slices: [LanguageAudioSlice] = []
        for index in sorted.indices {
            let start = sorted[index].1
            let end = index + 1 < sorted.count ? sorted[index + 1].1 : totalDuration
            guard end - start >= minimumSliceDuration else { continue }
            slices.append(
                LanguageAudioSlice(
                    language: sorted[index].0,
                    startTime: start,
                    endTime: end
                )
            )
        }
        return slices
    }

    static func shouldTranscribeInSlices(
        noteLanguage: AppLanguage,
        segments: [RecordingLanguageSegment]
    ) -> Bool {
        !noteLanguage.isAutoDetect && segments.count > 1
    }

    static func mergeTranscriptionResults(
        _ results: [(slice: LanguageAudioSlice, result: TranscriptionResult)]
    ) -> TranscriptionResult? {
        guard let first = results.first else { return nil }

        var mergedSegments: [TranscriptSegmentDTO] = []
        var fullTextParts: [String] = []
        var weightedConfidence = 0.0
        var totalWeight = 0.0
        var totalProcessingMs = 0
        var providerIds: [String] = []
        var metadata = first.result.metadata

        for entry in results {
            let offset = entry.slice.startTime
            let sliceSegments = entry.result.segments.map { segment in
                TranscriptSegmentDTO(
                    id: segment.id,
                    index: segment.index,
                    text: segment.text,
                    startTime: segment.startTime + offset,
                    endTime: segment.endTime + offset,
                    confidence: segment.confidence,
                    speakerLabel: segment.speakerLabel,
                    isUnclear: segment.isUnclear,
                    providerId: segment.providerId
                )
            }
            mergedSegments.append(contentsOf: sliceSegments)

            let trimmed = entry.result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                fullTextParts.append(trimmed)
            }

            let weight = max(entry.slice.duration, 0.1)
            weightedConfidence += entry.result.averageConfidence * weight
            totalWeight += weight
            totalProcessingMs += entry.result.processingTimeMs
            providerIds.append(entry.result.providerId)
        }

        mergedSegments = mergedSegments.enumerated().map { index, segment in
            TranscriptSegmentDTO(
                id: segment.id,
                index: index,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence,
                speakerLabel: segment.speakerLabel,
                isUnclear: segment.isUnclear,
                providerId: segment.providerId
            )
        }

        metadata["multiLanguage"] = "true"
        metadata["languages"] = results.map(\.slice.language.rawValue).joined(separator: ",")
        metadata["providers"] = providerIds.joined(separator: ",")

        return TranscriptionResult(
            providerId: providerIds.first ?? first.result.providerId,
            language: first.slice.language,
            segments: mergedSegments,
            fullText: fullTextParts.joined(separator: " "),
            averageConfidence: totalWeight > 0 ? weightedConfidence / totalWeight : first.result.averageConfidence,
            processingTimeMs: totalProcessingMs,
            metadata: metadata
        )
    }
}
