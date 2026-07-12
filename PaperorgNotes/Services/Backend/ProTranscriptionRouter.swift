import AVFoundation
import Foundation

enum AudioDurationReader {
    static func duration(for url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return 60 }
        return seconds
    }
}

@MainActor
final class ProTranscriptionRouter {
    private let registry: ProviderRegistry
    private let appleProvider = AppleSpeechProvider()

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let client = registry.proBackend
        let duration = AudioDurationReader.duration(for: request.audioURL)
        var lastError: Error?
        var attemptLog: [String] = []

        for provider in registry.orderedProviders(for: request.language) {
            if provider.identifier == ProviderID.apple.rawValue {
                do {
                    let result = try await appleProvider.transcribe(
                        request,
                        credentials: .from(registry.settings)
                    )
                    attemptLog.append("apple: succeeded on-device")
                    return tagged(result, attemptLog: attemptLog)
                } catch {
                    lastError = error
                    attemptLog.append("apple: failed — \(error.localizedDescription)")
                    continue
                }
            }

            let startedAt = Date()
            do {
                let result: TranscriptionResult
                switch provider.identifier {
                case ProviderID.luxasr.rawValue:
                    let data = try await client.transcribeLuxASR(
                        request: request,
                        durationSeconds: duration
                    )
                    result = try parseLuxASR(data, request: request, startedAt: startedAt)
                case ProviderID.elevenlabs.rawValue:
                    let data = try await client.transcribeElevenLabs(
                        request: request,
                        durationSeconds: duration
                    )
                    result = try parseElevenLabs(data, request: request, startedAt: startedAt)
                case ProviderID.openai.rawValue:
                    let data = try await client.transcribeOpenAI(
                        request: request,
                        durationSeconds: duration
                    )
                    result = try parseOpenAI(data, request: request, startedAt: startedAt)
                default:
                    continue
                }

                guard !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranscriptionError.emptyResult
                }
                attemptLog.append("\(provider.identifier): succeeded via Pro backend")
                return tagged(result, attemptLog: attemptLog)
            } catch {
                lastError = error
                attemptLog.append(
                    "\(provider.identifier): failed after \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s — \(error.localizedDescription)"
                )
            }
        }

        throw lastError ?? TranscriptionError.noProviderAvailable(request.language)
    }

    private func tagged(_ result: TranscriptionResult, attemptLog: [String]) -> TranscriptionResult {
        var metadata = result.metadata
        metadata["attemptLog"] = attemptLog.joined(separator: " | ")
        metadata["proBackend"] = "true"
        return TranscriptionResult(
            providerId: result.providerId,
            language: result.language,
            segments: result.segments,
            fullText: result.fullText,
            averageConfidence: result.averageConfidence,
            processingTimeMs: result.processingTimeMs,
            metadata: metadata
        )
    }

    private func parseOpenAI(_ data: Data, request: TranscriptionRequest, startedAt: Date) throws -> TranscriptionResult {
        let parsed = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        let segments: [TranscriptSegmentDTO]
        if let responseSegments = parsed.segments, !responseSegments.isEmpty {
            segments = responseSegments.enumerated().map { index, seg in
                TranscriptSegmentDTO(
                    index: index,
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: seg.start,
                    endTime: seg.end,
                    confidence: 0.85,
                    providerId: ProviderID.openai.rawValue
                )
            }
        } else {
            segments = [TranscriptSegmentDTO(
                index: 0,
                text: parsed.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: 0,
                endTime: parsed.duration ?? 0,
                confidence: 0.85,
                providerId: ProviderID.openai.rawValue
            )]
        }

        return TranscriptionResult(
            providerId: ProviderID.openai.rawValue,
            language: request.language,
            segments: segments,
            fullText: parsed.text,
            averageConfidence: 0.85,
            processingTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            metadata: ["model": "gpt-4o-transcribe", "proBackend": "true"]
        )
    }

    private func parseElevenLabs(_ data: Data, request: TranscriptionRequest, startedAt: Date) throws -> TranscriptionResult {
        let parsed = try JSONDecoder().decode(ElevenLabsResponse.self, from: data)
        let segments = buildElevenLabsSegments(from: parsed)
        let fullText = parsed.text ?? segments.map(\.text).joined(separator: " ")
        let avg = segments.map(\.confidence).reduce(0, +) / Double(max(segments.count, 1))
        return TranscriptionResult(
            providerId: ProviderID.elevenlabs.rawValue,
            language: request.language,
            segments: segments,
            fullText: fullText,
            averageConfidence: avg,
            processingTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            metadata: ["model": "scribe_v2", "proBackend": "true"]
        )
    }

    private func parseLuxASR(_ data: Data, request: TranscriptionRequest, startedAt: Date) throws -> TranscriptionResult {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = (json["text"] as? String) ?? (json["transcript"] as? String),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TranscriptionResult(
                providerId: ProviderID.luxasr.rawValue,
                language: request.language,
                segments: [TranscriptSegmentDTO(
                    index: 0,
                    text: text,
                    startTime: 0,
                    endTime: 0,
                    confidence: 0.85,
                    providerId: ProviderID.luxasr.rawValue
                )],
                fullText: text,
                averageConfidence: 0.85,
                processingTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                metadata: ["proBackend": "true"]
            )
        }

        let fallback = String(data: data, encoding: .utf8) ?? ""
        guard !fallback.isEmpty else { throw TranscriptionError.emptyResult }
        return TranscriptionResult(
            providerId: ProviderID.luxasr.rawValue,
            language: request.language,
            segments: [TranscriptSegmentDTO(
                index: 0,
                text: fallback,
                startTime: 0,
                endTime: 0,
                confidence: 0.85,
                providerId: ProviderID.luxasr.rawValue
            )],
            fullText: fallback,
            averageConfidence: 0.85,
            processingTimeMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            metadata: ["proBackend": "true"]
        )
    }

    private func buildElevenLabsSegments(from response: ElevenLabsResponse) -> [TranscriptSegmentDTO] {
        guard let words = response.words, !words.isEmpty else {
            return [TranscriptSegmentDTO(
                index: 0,
                text: response.text ?? "",
                startTime: 0,
                endTime: 0,
                confidence: 0.85,
                providerId: ProviderID.elevenlabs.rawValue
            )]
        }

        var segments: [TranscriptSegmentDTO] = []
        var currentWords: [ElevenLabsWord] = []
        for word in words {
            if let last = currentWords.last,
               word.start - last.end > 0.8,
               !currentWords.isEmpty {
                segments.append(makeElevenLabsSegment(from: currentWords, index: segments.count))
                currentWords = []
            }
            currentWords.append(word)
        }
        if !currentWords.isEmpty {
            segments.append(makeElevenLabsSegment(from: currentWords, index: segments.count))
        }
        return segments
    }

    private func makeElevenLabsSegment(from words: [ElevenLabsWord], index: Int) -> TranscriptSegmentDTO {
        let text = words.map(\.text).joined(separator: " ")
        let confidence = words.compactMap(\.confidence).reduce(0, +) / Double(max(words.compactMap(\.confidence).count, 1))
        return TranscriptSegmentDTO(
            index: index,
            text: text,
            startTime: words.first?.start ?? 0,
            endTime: words.last?.end ?? 0,
            confidence: confidence > 0 ? confidence : 0.85,
            speakerLabel: words.compactMap(\.speaker_id).first,
            providerId: ProviderID.elevenlabs.rawValue
        )
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
    let duration: Double?
    let segments: [OpenAISegment]?
}

private struct OpenAISegment: Decodable {
    let text: String
    let start: Double
    let end: Double
}

private struct ElevenLabsResponse: Decodable {
    let text: String?
    let words: [ElevenLabsWord]?
}

private struct ElevenLabsWord: Decodable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double?
    let speaker_id: String?
}
