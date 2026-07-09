import Foundation

final class LuxASRProvider: TranscriptionProvider, @unchecked Sendable {
    let identifier = ProviderID.luxasr.rawValue
    let displayName = ProviderID.luxasr.displayName
    let supportedLanguages: Set<AppLanguage> = [.luxembourgish]
    let supportsDiarization = true
    let supportsWordTimestamps = true
    
    private let baseURL = URL(string: "https://luxasr.uni.lu")!
    private let pollInterval: TimeInterval = 2.0
    private let maxPollAttempts = 120
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool {
        // LuxASR may work without key for limited access; key optional until required by server
        true
    }
    
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult {
        let start = Date()
        let audioData = try Data(contentsOf: request.audioURL)
        let mimeType = mimeType(for: request.audioURL)
        let filename = request.audioURL.lastPathComponent
        
        var components = URLComponents(url: baseURL.appendingPathComponent("asr2"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "language", value: "lb"),
            URLQueryItem(name: "diarization", value: request.enableDiarization ? "Enabled" : "Disabled"),
            URLQueryItem(name: "outfmt", value: "json")
        ]
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            // LuxASR ignores text beyond 900 characters
            let trimmed = String(prompt.prefix(900))
            queryItems.append(URLQueryItem(name: "prompt", value: trimmed))
        }
        components.queryItems = queryItems
        
        guard let submitURL = components.url else {
            throw TranscriptionError.providerError("Invalid LuxASR URL")
        }
        
        var submitRequest = URLRequest(url: submitURL)
        submitRequest.httpMethod = "POST"
        submitRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        submitRequest.setValue(filename, forHTTPHeaderField: "X-Filename")
        submitRequest.httpBody = audioData
        submitRequest.timeoutInterval = 120
        
        if let apiKey = credentials.luxASRAPIKey, !apiKey.isEmpty {
            submitRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (submitData, submitResponse) = try await URLSession.shared.data(for: submitRequest)
        
        guard let http = submitResponse as? HTTPURLResponse else {
            throw TranscriptionError.networkError("Invalid LuxASR submit response")
        }
        
        guard http.statusCode == 202 else {
            let msg = String(data: submitData, encoding: .utf8) ?? "Submit failed (HTTP \(http.statusCode))"
            throw TranscriptionError.providerError(msg)
        }
        
        let job = try JSONDecoder().decode(LuxASRJobResponse.self, from: submitData)
        
        let jobStatus = try await pollUntilComplete(jobId: job.job_id)
        
        guard jobStatus.status == "completed" else {
            throw TranscriptionError.providerError(jobStatus.error ?? "LuxASR job failed")
        }
        
        let resultURL = baseURL.appendingPathComponent("v3/asr/jobs/\(job.job_id)/result")
        let (resultData, resultResponse) = try await URLSession.shared.data(from: resultURL)
        
        if let http = resultResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: resultData, encoding: .utf8) ?? "Result fetch failed (HTTP \(http.statusCode))"
            throw TranscriptionError.providerError(msg)
        }
        
        return try parseLuxASRResult(resultData, language: request.language, start: start)
    }
    
    private func pollUntilComplete(jobId: String) async throws -> LuxASRStatusResponse {
        let statusURL = baseURL.appendingPathComponent("v3/asr/jobs/\(jobId)")
        
        for _ in 0..<maxPollAttempts {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            
            let (statusData, response) = try await URLSession.shared.data(from: statusURL)
            
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: statusData, encoding: .utf8) ?? "Status poll failed (HTTP \(http.statusCode))"
                throw TranscriptionError.providerError(msg)
            }
            
            let status = try JSONDecoder().decode(LuxASRStatusResponse.self, from: statusData)
            
            switch status.status {
            case "completed", "failed":
                return status
            case "queued", "processing":
                continue
            default:
                continue
            }
        }
        
        throw TranscriptionError.providerError("LuxASR job timed out")
    }
    
    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "mp2": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "mov": return "video/mp4"
        case "ogg": return "audio/ogg"
        case "webm": return "audio/webm"
        case "wmv", "wmav2": return "audio/x-ms-wmv"
        default: return "audio/mp4"
        }
    }
    
    private func parseLuxASRResult(_ data: Data, language: AppLanguage, start: Date) throws -> TranscriptionResult {
        // Try JSON first (outfmt=json)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let segments = parseJSONSegments(json)
            if !segments.isEmpty {
                return makeResult(segments: segments, language: language, start: start)
            }
        }
        
        // Fallback: plain text response (outfmt=text)
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            let segments = [TranscriptSegmentDTO(
                index: 0,
                text: text,
                startTime: 0,
                endTime: 0,
                confidence: 0.9,
                providerId: identifier
            )]
            return makeResult(segments: segments, language: language, start: start)
        }
        
        throw TranscriptionError.emptyResult
    }
    
    private func parseJSONSegments(_ json: [String: Any]) -> [TranscriptSegmentDTO] {
        var segments: [TranscriptSegmentDTO] = []
        
        if let segmentsArray = json["segments"] as? [[String: Any]] {
            for (index, seg) in segmentsArray.enumerated() {
                guard let text = seg["text"] as? String, !text.isEmpty else { continue }
                let startTime = seg["start"] as? Double ?? seg["start_time"] as? Double ?? 0
                let endTime = seg["end"] as? Double ?? seg["end_time"] as? Double ?? startTime
                let confidence = seg["confidence"] as? Double ?? 0.9
                let speaker = seg["speaker"] as? String ?? seg["speaker_id"] as? String
                segments.append(TranscriptSegmentDTO(
                    index: index,
                    text: text,
                    startTime: startTime,
                    endTime: endTime,
                    confidence: confidence,
                    speakerLabel: speaker,
                    providerId: identifier
                ))
            }
        } else if let text = json["text"] as? String ?? json["transcript"] as? String, !text.isEmpty {
            segments.append(TranscriptSegmentDTO(
                index: 0,
                text: text,
                startTime: 0,
                endTime: 0,
                confidence: 0.9,
                providerId: identifier
            ))
        }
        
        return segments
    }
    
    private func makeResult(segments: [TranscriptSegmentDTO], language: AppLanguage, start: Date) -> TranscriptionResult {
        let fullText = segments.map(\.text).joined(separator: " ")
        let avg = segments.map(\.confidence).reduce(0, +) / Double(max(segments.count, 1))
        
        return TranscriptionResult(
            providerId: identifier,
            language: language,
            segments: segments,
            fullText: fullText,
            averageConfidence: avg,
            processingTimeMs: Int(Date().timeIntervalSince(start) * 1000),
            metadata: ["source": "luxasr", "api_version": "v3"]
        )
    }
}

private struct LuxASRJobResponse: Decodable {
    let job_id: String
    let status: String
}

private struct LuxASRStatusResponse: Decodable {
    let status: String
    let error: String?
}
