import Foundation
import NaturalLanguage

enum AppLanguageDetector {
    static func resolve(
        openAICode: String? = nil,
        elevenLabsCode: String? = nil,
        transcript: String,
        fallback: AppLanguage
    ) -> AppLanguage {
        if let elevenLabsCode, let language = fromElevenLabs(elevenLabsCode) {
            return language
        }
        if let openAICode,
           let language = AppLanguage.fromTranscriptionCode(openAICode) {
            return language
        }
        return fromTranscript(transcript, fallback: fallback)
    }

    static func fromElevenLabs(_ code: String) -> AppLanguage? {
        switch code.lowercased() {
        case "ltz", "lb": return .luxembourgish
        case "deu", "de": return .german
        case "fra", "fr": return .french
        case "eng", "en": return .english
        case "por", "pt": return .portuguese
        default:
            return AppLanguage.fromTranscriptionCode(code)
        }
    }

    static func fromTranscript(_ text: String, fallback: AppLanguage) -> AppLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return fallback }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return fallback }

        if let mapped = AppLanguage.fromTranscriptionCode(dominant.rawValue) {
            return mapped
        }
        return fallback
    }
}
