import Foundation

struct LanguageAudioSlice: Sendable, Hashable {
    let language: AppLanguage
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }
}

/// Pure helpers for transcription language planning.
enum MergeableSession {
    /// One part stays within the 3-hour upload the live server accepts as a single file.
    static let partLimit: TimeInterval = 3 * 60 * 60

    static func isMergable(_ duration: TimeInterval) -> Bool {
        duration > partLimit + 1
    }

    static func parts(for duration: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
        guard isMergable(duration), duration > 0 else { return [(0, max(duration, 0))] }
        var pieces: [(start: TimeInterval, end: TimeInterval)] = []
        var start: TimeInterval = 0
        while start < duration - 0.05 {
            let end = min(start + partLimit, duration)
            guard end - start > 0.05 else { break }
            pieces.append((start, end))
            start = end
        }
        return pieces
    }

    static func partTitle(_ title: String, index: Int, count: Int) -> String {
        "\(title) · \(index + 1)/\(count)"
    }

    static func titleWithoutPartSuffix(_ title: String) -> String {
        guard let range = title.range(of: #" · \d+/\d+$"#, options: .regularExpression) else {
            return title
        }
        return String(title[..<range.lowerBound])
    }
}

enum LongRecordingTranscription {
    /// The live server refuses one upload over 100 MB, and a free account
    /// over 3 minutes. Two and a half minutes stays under both.
    static let chunkDuration: TimeInterval = 150
    static let maxUploadBytes = 8 * 1024 * 1024

    static func takesLonger(_ duration: TimeInterval) -> Bool {
        duration > chunkDuration + 1
    }

    static func chunks(
        of slice: LanguageAudioSlice,
        maximumChunkDuration: TimeInterval = chunkDuration
    ) -> [LanguageAudioSlice] {
        guard slice.duration > maximumChunkDuration + 0.05 else { return [slice] }

        var pieces: [LanguageAudioSlice] = []
        var start = slice.startTime
        while start < slice.endTime - 0.05 {
            let end = min(start + maximumChunkDuration, slice.endTime)
            guard end - start > 0.05 else { break }
            pieces.append(
                LanguageAudioSlice(language: slice.language, startTime: start, endTime: end)
            )
            start = end
        }
        return pieces
    }
}

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
        if hasMultipleRecordingLanguages {
            return .autoDetect
        }
        if noteLanguage.isAutoDetect {
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
        let boundaries = normalizedBoundaries(noteLanguage: noteLanguage, segments: segments)
        guard !boundaries.isEmpty else { return [] }

        if !noteLanguage.isAutoDetect, boundaries.count == 1, boundaries[0].1 == 0 {
            guard totalDuration >= minimumSliceDuration else { return [] }
            return [LanguageAudioSlice(language: boundaries[0].0, startTime: 0, endTime: totalDuration)]
        }

        guard boundaries.count > 1 else { return [] }

        var slices: [LanguageAudioSlice] = []
        for index in boundaries.indices {
            let start = boundaries[index].1
            let end = index + 1 < boundaries.count ? boundaries[index + 1].1 : totalDuration
            let duration = end - start
            let isLastSlice = index == boundaries.count - 1
            guard duration >= minimumSliceDuration || (isLastSlice && duration > 0.05) else { continue }
            slices.append(
                LanguageAudioSlice(
                    language: boundaries[index].0,
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
        if segments.count > 1 { return true }
        return noteLanguage.isAutoDetect && !segments.isEmpty
    }

    /// Merge stored segments with implicit auto-detect boundaries for auto-started notes.
    static func normalizedBoundaries(
        noteLanguage: AppLanguage,
        segments: [RecordingLanguageSegment]
    ) -> [(AppLanguage, TimeInterval)] {
        var boundaries = segments
            .sorted { $0.startTime < $1.startTime }
            .compactMap { segment -> (AppLanguage, TimeInterval)? in
                guard let language = AppLanguage(rawValue: segment.languageCode) else { return nil }
                return (language, segment.startTime)
            }

        guard noteLanguage.isAutoDetect, let first = boundaries.first else { return boundaries }

        if first.1 > 0.05, first.0 != .autoDetect {
            boundaries.insert((.autoDetect, 0), at: 0)
        }
        return boundaries
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
