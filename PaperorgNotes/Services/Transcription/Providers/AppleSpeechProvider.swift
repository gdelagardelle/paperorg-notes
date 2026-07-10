import Foundation
import Speech

final class AppleSpeechProvider: TranscriptionProvider, @unchecked Sendable {
    let identifier = ProviderID.apple.rawValue
    let displayName = ProviderID.apple.displayName
    let supportedLanguages: Set<AppLanguage> = [.english]
    let sendsAudioOffDevice = false
    let supportsDiarization = false
    let supportsWordTimestamps = false
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool {
        true
    }
    
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult {
        let start = Date()
        
        let authorized = await requestSpeechAuthorization()
        guard authorized else {
            throw TranscriptionError.providerError("Speech recognition permission denied")
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw TranscriptionError.providerError("Apple Speech not available for English")
        }
        
        let url = request.audioURL
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: url)
        recognitionRequest.shouldReportPartialResults = false
        
        let result = try await recognize(recognizer: recognizer, request: recognitionRequest)
        
        let text = result.bestTranscription.formattedString
        let segments = result.bestTranscription.segments.enumerated().map { index, seg in
            TranscriptSegmentDTO(
                index: index,
                text: seg.substring,
                startTime: seg.timestamp,
                endTime: seg.timestamp + seg.duration,
                confidence: Double(seg.confidence),
                providerId: identifier
            )
        }
        
        let groupedSegments = groupSegments(segments, fullText: text)
        let avg = groupedSegments.map(\.confidence).reduce(0, +) / Double(max(groupedSegments.count, 1))
        
        return TranscriptionResult(
            providerId: identifier,
            language: .english,
            segments: groupedSegments,
            fullText: text,
            averageConfidence: avg,
            processingTimeMs: Int(Date().timeIntervalSince(start) * 1000),
            metadata: ["on_device": "true"]
        )
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> SFSpeechRecognitionResult {
        let operation = RecognitionOperation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                operation.install(continuation: continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                        operation.finish(
                            .failure(TranscriptionError.providerError("Apple Speech could not transcribe this recording."))
                        )
                    return
                }
                guard let result, result.isFinal else { return }
                    operation.finish(.success(result))
                }
                operation.install(task: task)
                Task {
                    try? await Task.sleep(for: .seconds(120))
                    operation.timeout()
                }
            }
        }, onCancel: {
            operation.cancel()
        })
    }
    
    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    private func groupSegments(_ segments: [TranscriptSegmentDTO], fullText: String) -> [TranscriptSegmentDTO] {
        guard !segments.isEmpty else {
            return [TranscriptSegmentDTO(index: 0, text: fullText, startTime: 0, endTime: 0, confidence: 0.8, providerId: identifier)]
        }
        
        var grouped: [TranscriptSegmentDTO] = []
        var buffer: [TranscriptSegmentDTO] = []
        
        for seg in segments {
            buffer.append(seg)
            if buffer.count >= 8 || seg.text.hasSuffix(".") || seg.text.hasSuffix("?") || seg.text.hasSuffix("!") {
                let text = buffer.map(\.text).joined(separator: " ")
                grouped.append(TranscriptSegmentDTO(
                    index: grouped.count,
                    text: text,
                    startTime: buffer.first?.startTime ?? 0,
                    endTime: buffer.last?.endTime ?? 0,
                    confidence: buffer.map(\.confidence).reduce(0, +) / Double(buffer.count),
                    providerId: identifier
                ))
                buffer = []
            }
        }
        
        if !buffer.isEmpty {
            let text = buffer.map(\.text).joined(separator: " ")
            grouped.append(TranscriptSegmentDTO(
                index: grouped.count,
                text: text,
                startTime: buffer.first?.startTime ?? 0,
                endTime: buffer.last?.endTime ?? 0,
                confidence: buffer.map(\.confidence).reduce(0, +) / Double(buffer.count),
                providerId: identifier
            ))
        }
        
        return grouped
    }
}

private final class RecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>?
    private var task: SFSpeechRecognitionTask?
    private var finished = false

    func install(continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
    }

    func install(task: SFSpeechRecognitionTask) {
        lock.lock()
        defer { lock.unlock() }
        if finished {
            task.cancel()
        } else {
            self.task = task
        }
    }

    func finish(_ result: Result<SFSpeechRecognitionResult, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        task?.cancel()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func timeout() {
        finish(.failure(TranscriptionError.providerError("Apple Speech timed out. Please try again.")))
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}
