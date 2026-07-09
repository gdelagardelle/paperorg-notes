import Foundation

final class ElevenLabsScribeProvider: TranscriptionProvider, @unchecked Sendable {
    let identifier = ProviderID.elevenlabs.rawValue
    let displayName = ProviderID.elevenlabs.displayName
    let supportedLanguages: Set<AppLanguage> = [.luxembourgish, .german, .french, .english, .portuguese]
    let supportsDiarization = true
    let supportsWordTimestamps = true
    
    private let baseURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool {
        credentials.elevenLabsAPIKey?.isEmpty == false
    }
    
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult {
        guard let apiKey = credentials.elevenLabsAPIKey, !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey(.elevenlabs)
        }
        
        let start = Date()
        let audioData = try AudioFileReader.readData(from: request.audioURL)
        let boundary = UUID().uuidString
        var body = Data()
        
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("model_id", "scribe_v2")
        appendField("language_code", request.language.elevenLabsCode)
        appendField("timestamps_granularity", "word")
        appendField("diarize", request.enableDiarization ? "true" : "false")
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 300
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "ElevenLabs error"
            throw TranscriptionError.providerError(msg)
        }
        
        let parsed = try JSONDecoder().decode(ElevenLabsResponse.self, from: data)
        let segments = buildSegments(from: parsed)
        let fullText = parsed.text ?? segments.map(\.text).joined(separator: " ")
        let avg = segments.map(\.confidence).reduce(0, +) / Double(max(segments.count, 1))
        
        return TranscriptionResult(
            providerId: identifier,
            language: request.language,
            segments: segments,
            fullText: fullText,
            averageConfidence: avg,
            processingTimeMs: Int(Date().timeIntervalSince(start) * 1000),
            metadata: ["model": "scribe_v2"]
        )
    }
    
    private func buildSegments(from response: ElevenLabsResponse) -> [TranscriptSegmentDTO] {
        guard let words = response.words, !words.isEmpty else {
            return [TranscriptSegmentDTO(
                index: 0,
                text: response.text ?? "",
                startTime: 0,
                endTime: 0,
                confidence: 0.85,
                providerId: identifier
            )]
        }
        
        // Group words into sentence-like segments by pauses > 0.8s
        var segments: [TranscriptSegmentDTO] = []
        var currentWords: [ElevenLabsWord] = []
        
        for word in words {
            if let last = currentWords.last,
               word.start - last.end > 0.8,
               !currentWords.isEmpty {
                segments.append(makeSegment(from: currentWords, index: segments.count))
                currentWords = []
            }
            currentWords.append(word)
        }
        if !currentWords.isEmpty {
            segments.append(makeSegment(from: currentWords, index: segments.count))
        }
        
        return segments
    }
    
    private func makeSegment(from words: [ElevenLabsWord], index: Int) -> TranscriptSegmentDTO {
        let text = words.map(\.text).joined(separator: " ")
        let confidence = words.compactMap(\.confidence).reduce(0, +) / Double(max(words.compactMap(\.confidence).count, 1))
        let speaker = words.compactMap(\.speaker_id).first
        return TranscriptSegmentDTO(
            index: index,
            text: text,
            startTime: words.first?.start ?? 0,
            endTime: words.last?.end ?? 0,
            confidence: confidence > 0 ? confidence : 0.85,
            speakerLabel: speaker,
            providerId: identifier
        )
    }
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
