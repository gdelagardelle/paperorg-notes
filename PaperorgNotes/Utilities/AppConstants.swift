import Foundation

enum AppConstants {
    static let appGroupID = "group.com.paperorg.notes"
    static let urlScheme = "paperorgnotes"
    
    enum UserDefaultsKeys {
        static let quickRecordLanguage = "quickRecordLanguage"
        static let quickRecordOutputType = "quickRecordOutputType"
        static let pendingQuickRecord = "pendingQuickRecord"
        static let quickRecordRequestedAt = "quickRecordRequestedAt"
    }
    
    static var recordDeepLink: URL {
        URL(string: "\(urlScheme)://record")!
    }
}

enum SpeakerLabelFormatter {
    static func displayName(for raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        
        if raw.uppercased().hasPrefix("SPEAKER_") {
            let suffix = raw.uppercased().replacingOccurrences(of: "SPEAKER_", with: "")
            if let number = Int(suffix) {
                return "Speaker \(number + 1)"
            }
        }
        
        switch raw.lowercased() {
        case "agent", "speaker_0": return "Speaker 1"
        case "customer", "speaker_1": return "Speaker 2"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    static func colorIndex(for raw: String?) -> Int {
        guard let raw else { return 0 }
        if let last = raw.split(separator: "_").last, let n = Int(last) {
            return n
        }
        return abs(raw.hashValue) % 4
    }
}

enum VocabularyFormatter {
    static func prompt(from terms: [String]) -> String? {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !cleaned.isEmpty else { return nil }
        
        let joined = cleaned.prefix(40).joined(separator: ", ")
        return String(joined.prefix(900))
    }
}
