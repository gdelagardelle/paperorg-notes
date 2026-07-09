import Foundation

enum TranscriptTextFormatter {
    /// Extracts readable text from a transcript string that may be raw LuxASR JSON.
    static func readableText(from raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.hasPrefix("[") || trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return trimmed
        }
        
        if let segments = json as? [[String: Any]] {
            let text = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        
        if let dict = json as? [String: Any],
           let segments = dict["segments"] as? [[String: Any]] {
            let text = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        
        if let dict = json as? [String: Any],
           let text = dict["text"] as? String ?? dict["transcript"] as? String,
           !text.isEmpty {
            return text
        }
        
        return nil
    }
    
    static func isRawJSON(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix("[") || text.hasPrefix("{") else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
