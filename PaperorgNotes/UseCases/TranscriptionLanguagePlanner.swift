import Foundation

/// Pure helpers for auto-detect transcription (Track A).
enum TranscriptionLanguagePlanner {
    static func requestLanguage(for noteLanguage: AppLanguage) -> AppLanguage {
        noteLanguage.isAutoDetect ? .autoDetect : noteLanguage
    }

    /// After auto-detect resolves to Luxembourgish via OpenAI/ElevenLabs, retry with LuxASR.
    static func shouldUpgradeAutoDetectToLuxASR(
        wasAutoDetect: Bool,
        resolvedLanguage: AppLanguage,
        providerId: String,
        luxasrEnabled: Bool
    ) -> Bool {
        wasAutoDetect
            && resolvedLanguage == .luxembourgish
            && luxasrEnabled
            && providerId != ProviderID.luxasr.rawValue
    }

    static func summaryLanguage(
        resolvedLanguage: AppLanguage,
        noteLanguage: AppLanguage,
        fallback: AppLanguage
    ) -> AppLanguage {
        if noteLanguage.isAutoDetect {
            return resolvedLanguage.isAutoDetect ? fallback : resolvedLanguage
        }
        return resolvedLanguage.isAutoDetect ? fallback : resolvedLanguage
    }
}
