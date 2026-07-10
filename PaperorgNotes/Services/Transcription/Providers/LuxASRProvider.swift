import Foundation

final class LuxASRProvider: TranscriptionProvider, @unchecked Sendable {
    let identifier = ProviderID.luxasr.rawValue
    let displayName = ProviderID.luxasr.displayName
    let supportedLanguages: Set<AppLanguage> = [.luxembourgish]
    let supportsDiarization = true
    let supportsWordTimestamps = true
    
    private let baseURL = URL(string: "https://luxasr.uni.lu")!
    private let pollInterval: TimeInterval = 2.0
    // A free/academic LuxASR queue can stall for a long time. Fail over promptly
    // instead of holding the processing UI for several minutes.
    private let maxPollAttempts = 30
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool {
        // LuxASR may work without key for limited access; key optional until required by server
        true
    }
    
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult {
        let start = Date()
        let audioData = try AudioFileReader.readData(from: request.audioURL)
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
        
        let pollResult = try await pollUntilComplete(jobId: job.job_id, apiKey: credentials.luxASRAPIKey)
        let jobStatus = pollResult.status
        
        guard jobStatus.status == "completed" else {
            throw TranscriptionError.providerError(jobStatus.error ?? "LuxASR job failed")
        }
        
        var resultComponents = URLComponents(
            url: baseURL.appendingPathComponent("v3/asr/jobs/\(job.job_id)/result"),
            resolvingAgainstBaseURL: false
        )!
        resultComponents.queryItems = [URLQueryItem(name: "_", value: UUID().uuidString)]
        guard let resultURL = resultComponents.url else {
            throw TranscriptionError.providerError("Invalid LuxASR result URL")
        }
        var resultRequest = URLRequest(url: resultURL)
        resultRequest.timeoutInterval = 20
        resultRequest.cachePolicy = .reloadIgnoringLocalCacheData
        resultRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let apiKey = credentials.luxASRAPIKey, !apiKey.isEmpty {
            resultRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (resultData, resultResponse) = try await URLSession.shared.data(for: resultRequest)
        
        if let http = resultResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: resultData, encoding: .utf8) ?? "Result fetch failed (HTTP \(http.statusCode))"
            throw TranscriptionError.providerError(msg)
        }
        
        let parsed = try parseLuxASRResult(resultData, language: request.language, start: start)
        var metadata = parsed.metadata
        metadata["jobId"] = job.job_id
        metadata["pollHistory"] = pollResult.history.joined(separator: " | ")
        return TranscriptionResult(
            providerId: parsed.providerId,
            language: parsed.language,
            segments: parsed.segments,
            fullText: parsed.fullText,
            averageConfidence: parsed.averageConfidence,
            processingTimeMs: parsed.processingTimeMs,
            metadata: metadata
        )
    }
    
    private func pollUntilComplete(jobId: String, apiKey: String?) async throws -> LuxASRPollResult {
        let statusBaseURL = baseURL.appendingPathComponent("v3/asr/jobs/\(jobId)")
        var lastStatus = "no status response"
        var history: [String] = []
        let startedAt = Date()
        
        for attempt in 0..<maxPollAttempts {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
            
            var components = URLComponents(url: statusBaseURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "_", value: UUID().uuidString)]
            guard let statusURL = components.url else {
                throw TranscriptionError.providerError("Invalid LuxASR status URL")
            }
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.timeoutInterval = 20
            statusRequest.cachePolicy = .reloadIgnoringLocalCacheData
            statusRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if let apiKey, !apiKey.isEmpty {
                statusRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            let (statusData, response) = try await URLSession.shared.data(for: statusRequest)
            
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: statusData, encoding: .utf8) ?? "Status poll failed (HTTP \(http.statusCode))"
                throw TranscriptionError.providerError(msg)
            }
            
            let status = try JSONDecoder().decode(LuxASRStatusResponse.self, from: statusData)
            lastStatus = status.status
            history.append("+\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s: \(status.status)")
            
            switch status.status {
            case "completed", "failed":
                return LuxASRPollResult(status: status, history: history)
            case "queued", "processing":
                continue
            default:
                continue
            }
        }
        
        throw TranscriptionError.providerError(
            "LuxASR timed out after \(Int(pollInterval * Double(maxPollAttempts))) seconds (last status: \(lastStatus))."
        )
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
        if let object = try? JSONSerialization.jsonObject(with: data) {
            let segments = parseJSONSegments(from: object)
            if !segments.isEmpty {
                return makeResult(segments: segments, language: language, start: start)
            }
        }
        
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("[") && !text.hasPrefix("{") {
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
    
    private func parseJSONSegments(from object: Any) -> [TranscriptSegmentDTO] {
        if let rootArray = object as? [[String: Any]] {
            return rootArray.enumerated().compactMap { index, seg in
                parseSegmentDictionary(seg, index: index)
            }
        }
        
        if let json = object as? [String: Any] {
            if let segmentsArray = json["segments"] as? [[String: Any]] {
                return segmentsArray.enumerated().compactMap { index, seg in
                    parseSegmentDictionary(seg, index: index)
                }
            }
            if let text = json["text"] as? String ?? json["transcript"] as? String, !text.isEmpty {
                return [TranscriptSegmentDTO(
                    index: 0,
                    text: text,
                    startTime: 0,
                    endTime: 0,
                    confidence: 0.9,
                    providerId: identifier
                )]
            }
        }
        
        return []
    }
    
    private func parseSegmentDictionary(_ seg: [String: Any], index: Int) -> TranscriptSegmentDTO? {
        guard let text = seg["text"] as? String, !text.isEmpty else { return nil }
        
        let startTime = seg["start"] as? Double ?? seg["start_time"] as? Double ?? 0
        let endTime = seg["end"] as? Double ?? seg["end_time"] as? Double ?? startTime
        let speaker = seg["speaker"] as? String ?? seg["speaker_id"] as? String
        
        var confidence = seg["confidence"] as? Double ?? 0.9
        if let words = seg["words"] as? [[String: Any]], !words.isEmpty {
            let probs = words.compactMap { $0["probability"] as? Double }
            if !probs.isEmpty {
                confidence = probs.reduce(0, +) / Double(probs.count)
            }
        }
        
        return TranscriptSegmentDTO(
            index: index,
            text: text,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            speakerLabel: speaker,
            isUnclear: confidence < 0.55,
            providerId: identifier
        )
    }
    
    private func parseJSONSegments(_ json: [String: Any]) -> [TranscriptSegmentDTO] {
        parseJSONSegments(from: json)
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

private struct LuxASRPollResult {
    let status: LuxASRStatusResponse
    let history: [String]
}
