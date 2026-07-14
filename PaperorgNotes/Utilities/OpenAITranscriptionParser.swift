import Foundation

enum OpenAITranscriptionParser {
    struct Response {
        let text: String
        let duration: Double?
        let segments: [Segment]?
    }

    struct Segment {
        let text: String
        let start: Double
        let end: Double
    }

    static func parse(_ data: Data) throws -> Response {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty {
                throw TranscriptionError.providerError(detail)
            }
            if let message = object["message"] as? String, object["error"] != nil {
                throw TranscriptionError.providerError(message)
            }
            if let text = extractText(from: object), !text.isEmpty {
                return Response(
                    text: text,
                    duration: object["duration"] as? Double,
                    segments: parseSegments(from: object)
                )
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("{") {
            return Response(text: text, duration: nil, segments: nil)
        }

        throw TranscriptionError.providerError("Could not parse transcription response.")
    }

    private static func extractText(from object: [String: Any]) -> String? {
        if let text = object["text"] as? String { return text }
        if let transcript = object["transcript"] as? String { return transcript }
        return nil
    }

    private static func parseSegments(from object: [String: Any]) -> [Segment]? {
        guard let raw = object["segments"] as? [[String: Any]], !raw.isEmpty else { return nil }
        let segments = raw.compactMap { item -> Segment? in
            guard let text = item["text"] as? String else { return nil }
            let start = (item["start"] as? Double) ?? (item["start"] as? NSNumber)?.doubleValue ?? 0
            let end = (item["end"] as? Double) ?? (item["end"] as? NSNumber)?.doubleValue ?? start
            return Segment(text: text, start: start, end: end)
        }
        return segments.isEmpty ? nil : segments
    }
}
