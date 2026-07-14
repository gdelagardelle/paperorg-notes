import Foundation

enum SMTPProviderPreset: String, CaseIterable, Identifiable {
    case appleMail
    case outlook
    case gmail
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMail: return "Apple Mail"
        case .outlook: return "Outlook"
        case .gmail: return "Gmail"
        case .custom: return "Custom"
        }
    }

    var smtpHost: String? {
        switch self {
        case .appleMail: return "smtp.mail.me.com"
        case .outlook: return "smtp-mail.outlook.com"
        case .gmail: return "smtp.gmail.com"
        case .custom: return nil
        }
    }

    var smtpPort: Int { 465 }

    var setupHint: String {
        switch self {
        case .appleMail:
            return "Same account as Apple Mail on this iPhone. Use your @icloud.com, @me.com, or @mac.com address and an app-specific password from appleid.apple.com → Sign-In and Security → App-Specific Passwords."
        case .outlook:
            return "Use your Outlook address and an app password from account.microsoft.com (required if two-step verification is on)."
        case .gmail:
            return "Use your Gmail address and an app password from myaccount.google.com/apppasswords (required if two-step verification is on)."
        case .custom:
            return "Enter the SMTP server details from your email provider. Use port 465 with an app password when available."
        }
    }
}
