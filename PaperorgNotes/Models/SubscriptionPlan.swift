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

    init(
        isPro: Bool,
        minutesLimit: Int,
        minutesUsed: Double,
        minutesRemaining: Double,
        periodKey: String,
        proExpiresAt: String?
    ) {
        self.isPro = isPro
        self.minutesLimit = minutesLimit
        self.minutesUsed = minutesUsed
        self.minutesRemaining = minutesRemaining
        self.periodKey = periodKey
        self.proExpiresAt = proExpiresAt
    }

    /// Decodes both the legacy Notes backend shape (flat fields, integer
    /// minutes_limit) and the Paperorg Platform shapes: register/refresh
    /// nest the same flat fields with float limits, and GET /v1/usage wraps
    /// them in a `metrics` envelope keyed by metric name.
    init(from decoder: Decoder) throws {
        let platform = try decoder.container(keyedBy: PlatformKeys.self)
        if platform.contains(.metrics) {
            let metrics = try platform.decode([String: PlatformMetric].self, forKey: .metrics)
            let minutes = metrics["transcription.minutes"]
            isPro = try platform.decode(Bool.self, forKey: .isPro)
            minutesLimit = Int(minutes?.limit ?? 0)
            minutesUsed = minutes?.used ?? 0
            minutesRemaining = minutes?.remaining ?? 0
            periodKey = try platform.decode(String.self, forKey: .periodKey)
            proExpiresAt = try platform.decodeIfPresent(String.self, forKey: .proExpiresAt)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try container.decode(Bool.self, forKey: .isPro)
        if let intLimit = try? container.decode(Int.self, forKey: .minutesLimit) {
            minutesLimit = intLimit
        } else {
            minutesLimit = Int(try container.decode(Double.self, forKey: .minutesLimit))
        }
        minutesUsed = try container.decode(Double.self, forKey: .minutesUsed)
        minutesRemaining = try container.decode(Double.self, forKey: .minutesRemaining)
        periodKey = try container.decode(String.self, forKey: .periodKey)
        proExpiresAt = try container.decodeIfPresent(String.self, forKey: .proExpiresAt)
    }

    private enum PlatformKeys: String, CodingKey {
        case metrics
        case isPro = "is_pro"
        case periodKey = "period_key"
        case proExpiresAt = "pro_expires_at"
    }

    private struct PlatformMetric: Decodable {
        let used: Double
        let limit: Double?
        let remaining: Double?
    }

    var usageProgress: Double {
        guard minutesLimit > 0 else { return 0 }
        return min(1, max(0, minutesUsed / Double(minutesLimit)))
    }

    var periodDisplayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: periodKey) else { return periodKey }
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var proExpiryDisplay: String? {
        guard let proExpiresAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let date = iso.date(from: proExpiresAt) ?? fallback.date(from: proExpiresAt)
        guard let date else { return nil }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
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
