import Foundation

@MainActor
final class QualityPipeline {
    private let orchestrator: TranscriptionOrchestrator
    private let confidenceThreshold: Double = 0.55
    private let retranscribeThreshold: Double = 0.45
    
    init(orchestrator: TranscriptionOrchestrator) {
        self.orchestrator = orchestrator
    }
    
    func process(
        initialResult: TranscriptionResult,
        audioURL: URL,
        expectedLanguage: AppLanguage,
        prompt: String? = nil
    ) async throws -> FinalTranscript {
        var segments = initialResult.segments
        let providersUsed = [initialResult.providerId]
        let retranscribedCount = 0
        
        // Step 1: Flag low confidence segments
        segments = segments.map { seg in
            var updated = seg
            if seg.confidence < confidenceThreshold {
                updated.isUnclear = true
            }
            return updated
        }
        
        // Step 2: Detect suspicious phrases
        let suspicious = detectSuspiciousPhrases(in: segments)
        
        // Step 3: Detect mixed language segments
        let mixedLanguage = detectMixedLanguageSegments(in: segments, expected: expectedLanguage)
        
        // Step 4: Re-transcribe weak segments — disabled because providers ignore
        // segmentTimeRange and each attempt re-processes the entire file (very slow for LuxASR).
        let weakSegments = segments.filter { $0.confidence < retranscribeThreshold || $0.isUnclear }
        _ = weakSegments
        
        // Step 5: Language validation
        let languagePassed = validateLanguage(segments: segments, expected: expectedLanguage)
        
        // Step 6: Build final text — never invent words
        let fullText = segments.map { seg -> String in
            if seg.isUnclear && !seg.text.contains("[unclear]") {
                return seg.text + " [unclear]"
            }
            return seg.text
        }.joined(separator: " ")
        
        let avgConfidence = segments.map(\.confidence).reduce(0, +) / Double(max(segments.count, 1))
        
        let report = QualityReport(
            overallConfidence: avgConfidence,
            languageValidationPassed: languagePassed,
            detectedLanguage: expectedLanguage,
            lowConfidenceSegmentIds: segments.filter { $0.isUnclear }.map(\.id),
            suspiciousPhrases: suspicious,
            mixedLanguageSegments: mixedLanguage,
            providersUsed: providersUsed,
            retranscribedSegmentCount: retranscribedCount
        )
        
        return FinalTranscript(
            segments: segments,
            fullText: fullText,
            qualityReport: report,
            primaryProvider: initialResult.providerId
        )
    }
    
    private func detectSuspiciousPhrases(in segments: [TranscriptSegmentDTO]) -> [SuspiciousPhrase] {
        var results: [SuspiciousPhrase] = []
        
        for seg in segments {
            // Repeated characters (e.g., "aaaa")
            if seg.text.range(of: #"(.)\1{4,}"#, options: .regularExpression) != nil {
                results.append(SuspiciousPhrase(segmentIndex: seg.index, reason: "repeated_characters", text: seg.text))
            }
            
            // Very short segments with low confidence
            if seg.text.split(separator: " ").count <= 1 && seg.confidence < 0.4 {
                results.append(SuspiciousPhrase(segmentIndex: seg.index, reason: "low_confidence", text: seg.text))
            }
            
            // Placeholder patterns
            if seg.text.contains("...") && seg.confidence < 0.5 {
                results.append(SuspiciousPhrase(segmentIndex: seg.index, reason: "incomplete", text: seg.text))
            }
        }
        
        return results
    }
    
    private func detectMixedLanguageSegments(in segments: [TranscriptSegmentDTO], expected: AppLanguage) -> [MixedLanguageSegment] {
        var results: [MixedLanguageSegment] = []
        
        let frenchMarkers = [" le ", " la ", " les ", " des ", " une ", " est ", " nous "]
        let germanMarkers = [" der ", " die ", " das ", " und ", " ist ", " nicht "]
        let englishMarkers = [" the ", " and ", " is ", " are ", " was ", " have "]
        
        for seg in segments {
            let lower = " \(seg.text.lowercased()) "
            var detected: String?
            
            if expected != .french && frenchMarkers.contains(where: { lower.contains($0) }) {
                detected = "fr"
            } else if expected != .german && germanMarkers.contains(where: { lower.contains($0) }) {
                detected = "de"
            } else if expected != .english && englishMarkers.contains(where: { lower.contains($0) }) {
                detected = "en"
            }
            
            if let detected {
                results.append(MixedLanguageSegment(
                    segmentIndex: seg.index,
                    detectedLanguage: detected,
                    text: seg.text
                ))
            }
        }
        
        return results
    }
    
    private func validateLanguage(segments: [TranscriptSegmentDTO], expected: AppLanguage) -> Bool {
        // Heuristic: if >30% segments flagged as mixed language, validation fails
        let mixedCount = detectMixedLanguageSegments(in: segments, expected: expected).count
        return Double(mixedCount) / Double(max(segments.count, 1)) < 0.3
    }
}
