import Foundation

enum SubscriptionPlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Paperorg Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Use your own OpenAI & ElevenLabs API keys"
        case .pro:
            return "Transcription & summaries included — no keys needed"
        }
    }
}

struct ProUsageInfo: Codable, Sendable, Equatable {
    let isPro: Bool
    let minutesLimit: Int
    let minutesUsed: Double
    let minutesRemaining: Double
    let periodKey: String
    let proExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case isPro = "is_pro"
        case minutesLimit = "minutes_limit"
        case minutesUsed = "minutes_used"
        case minutesRemaining = "minutes_remaining"
        case periodKey = "period_key"
        case proExpiresAt = "pro_expires_at"
    }
}

enum ProBackendError: LocalizedError {
    case notAuthenticated
    case subscriptionRequired
    case usageLimitReached
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Could not connect to Paperorg Pro. Try again in Settings."
        case .subscriptionRequired:
            return "Paperorg Pro subscription required."
        case .usageLimitReached:
            return "You've used all included Pro minutes this month."
        case .serverError(let message):
            return message
        }
    }
}

enum SubscriptionProduct {
    static let proMonthly = "com.paperorg.notes.pro.monthly"
}
