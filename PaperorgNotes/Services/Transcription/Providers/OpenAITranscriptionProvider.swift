import Foundation

final class OpenAITranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    let identifier = ProviderID.openai.rawValue
    let displayName = ProviderID.openai.displayName
    let supportedLanguages: Set<AppLanguage> = [.luxembourgish, .german, .french, .english, .portuguese]
    let supportsDiarization = false
    let supportsWordTimestamps = true
    
    private let baseURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool {
        credentials.openAIAPIKey?.isEmpty == false
    }
    
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult {
        guard let apiKey = credentials.openAIAPIKey, !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey(.openai)
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
        
        // gpt-4o-transcribe supports "json" or "text" — not verbose_json
        appendField("model", "gpt-4o-transcribe")
        if let languageCode = request.language.openAITranscriptionCode {
            appendField("language", languageCode)
        }
        appendField("response_format", "json")
        
        if let prompt = combinedPrompt(for: request) {
            appendField("prompt", prompt)
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 300
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.networkError("Invalid response")
        }
        
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.providerError(message)
        }
        
        let parsed = try OpenAITranscriptionParser.parse(data)
        let segments: [TranscriptSegmentDTO]
        
        if let responseSegments = parsed.segments, !responseSegments.isEmpty {
            segments = responseSegments.enumerated().map { index, seg in
                TranscriptSegmentDTO(
                    index: index,
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: seg.start,
                    endTime: seg.end,
                    confidence: 0.85,
                    providerId: identifier
                )
            }
        } else {
            segments = [TranscriptSegmentDTO(
                index: 0,
                text: parsed.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: 0,
                endTime: parsed.duration ?? 0,
                confidence: 0.85,
                providerId: identifier
            )]
        }
        
        guard !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionError.emptyResult
        }
        
        let avgConfidence = segments.map(\.confidence).reduce(0, +) / Double(max(segments.count, 1))
        let resolvedLanguage = request.autoDetect
            ? AppLanguageDetector.resolve(
                openAICode: parsed.language,
                transcript: parsed.text,
                fallback: request.fallbackLanguage
            )
            : request.language
        
        return TranscriptionResult(
            providerId: identifier,
            language: resolvedLanguage,
            segments: segments,
            fullText: parsed.text,
            averageConfidence: avgConfidence,
            processingTimeMs: Int(Date().timeIntervalSince(start) * 1000),
            metadata: ["model": "gpt-4o-transcribe"]
        )
    }
    
    private func combinedPrompt(for request: TranscriptionRequest) -> String? {
        var parts: [String] = []
        if let hint = request.language.openAITranscriptionPromptHint {
            parts.append(hint)
        }
        if let vocabulary = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !vocabulary.isEmpty {
            parts.append(vocabulary)
        }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: " ").prefix(900))
    }
}
