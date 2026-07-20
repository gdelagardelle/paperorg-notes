import Foundation
import Observation

@Observable
@MainActor
final class SettingsService {
    private let keychain: KeychainService
    private let defaults: UserDefaults
    
    private enum Keys {
        static let defaultLanguage = "defaultLanguage"
        static let autoDetectLanguage = "autoDetectLanguage"
        static let providerPreferences = "providerPreferences"
        static let defaultOutputType = "defaultOutputType"
        static let summaryLength = "summaryLength"
        static let keepAudioFiles = "keepAudioFiles"
        static let deleteAudioAfterDays = "deleteAudioAfterDays"
        static let emailRecipients = "emailRecipients"
        static let emailPolicy = "emailPolicy"
        static let emailContent = "emailContent"
        static let emailAttachAudio = "emailAttachAudio"
        static let emailAttachPDF = "emailAttachPDF"
        static let emailAttachMarkdown = "emailAttachMarkdown"
        static let faceIDEnabled = "faceIDEnabled"
        static let hasAcceptedPrivacyPolicy = "hasAcceptedPrivacyPolicy"
        static let consentedProviders = "consentedProviders"
        static let deleteAudioAfterTranscription = "deleteAudioAfterTranscription"
        static let customVocabulary = "customVocabulary"
        static let reviewBeforeEmail = "reviewBeforeEmail"
        static let sendEmailAfterTranscription = "sendEmailAfterTranscription"
        static let useOwnMailServerForEmail = "useOwnMailServerForEmail"
        static let smtpHost = "smtpHost"
        static let smtpPort = "smtpPort"
        static let smtpUsername = "smtpUsername"
        static let smtpFromAddress = "smtpFromAddress"
        static let smtpProviderPreset = "smtpProviderPreset"
        static let selectedPlan = "selectedPlan"
        static let hasCompletedPlanSelection = "hasCompletedPlanSelection"
        static let proBackendBaseURL = "proBackendBaseURL"
        static let platformAPIBaseURL = "platformAPIBaseURL"
        static let usePlatformAuth = "usePlatformAuth"
        static let exportBrandName = "exportBrandName"
        static let exportBrandSubtitle = "exportBrandSubtitle"
        static let cachedProUsage = "cachedProUsage"
        static let platformUserID = "platformUserID"
    }
    
    var defaultLanguage: AppLanguage {
        didSet { defaults.set(defaultLanguage.rawValue, forKey: Keys.defaultLanguage) }
    }
    
    var autoDetectLanguage: Bool {
        didSet { defaults.set(autoDetectLanguage, forKey: Keys.autoDetectLanguage) }
    }
    
    var defaultOutputType: OutputType {
        didSet { defaults.set(defaultOutputType.rawValue, forKey: Keys.defaultOutputType) }
    }
    
    var summaryLength: SummaryLength {
        didSet { defaults.set(summaryLength.rawValue, forKey: Keys.summaryLength) }
    }
    
    var keepAudioFiles: Bool {
        didSet { defaults.set(keepAudioFiles, forKey: Keys.keepAudioFiles) }
    }
    
    var deleteAudioAfterDays: Int? {
        didSet {
            if let deleteAudioAfterDays {
                defaults.set(deleteAudioAfterDays, forKey: Keys.deleteAudioAfterDays)
            } else {
                defaults.removeObject(forKey: Keys.deleteAudioAfterDays)
            }
        }
    }
    
    var deleteAudioAfterTranscription: Bool {
        didSet { defaults.set(deleteAudioAfterTranscription, forKey: Keys.deleteAudioAfterTranscription) }
    }
    
    var emailRecipients: [String] {
        didSet { defaults.set(emailRecipients, forKey: Keys.emailRecipients) }
    }
    
    var emailPolicy: EmailPolicy {
        didSet { defaults.set(emailPolicy.rawValue, forKey: Keys.emailPolicy) }
    }
    
    var emailContent: EmailContent {
        didSet { defaults.set(emailContent.rawValue, forKey: Keys.emailContent) }
    }
    
    var emailAttachAudio: Bool {
        didSet { defaults.set(emailAttachAudio, forKey: Keys.emailAttachAudio) }
    }
    
    var emailAttachPDF: Bool {
        didSet { defaults.set(emailAttachPDF, forKey: Keys.emailAttachPDF) }
    }
    
    var emailAttachMarkdown: Bool {
        didSet { defaults.set(emailAttachMarkdown, forKey: Keys.emailAttachMarkdown) }
    }
    
    var faceIDEnabled: Bool {
        didSet { defaults.set(faceIDEnabled, forKey: Keys.faceIDEnabled) }
    }
    
    var hasAcceptedPrivacyPolicy: Bool {
        didSet { defaults.set(hasAcceptedPrivacyPolicy, forKey: Keys.hasAcceptedPrivacyPolicy) }
    }
    
    var consentedProviders: Set<String> {
        didSet { defaults.set(Array(consentedProviders), forKey: Keys.consentedProviders) }
    }
    
    var customVocabulary: [String] {
        didSet { defaults.set(customVocabulary, forKey: Keys.customVocabulary) }
    }
    
    var reviewBeforeEmail: Bool {
        didSet { defaults.set(reviewBeforeEmail, forKey: Keys.reviewBeforeEmail) }
    }

    var sendEmailAfterTranscription: Bool {
        didSet { defaults.set(sendEmailAfterTranscription, forKey: Keys.sendEmailAfterTranscription) }
    }

    var useOwnMailServerForEmail: Bool {
        didSet { defaults.set(useOwnMailServerForEmail, forKey: Keys.useOwnMailServerForEmail) }
    }

    var smtpHost: String {
        didSet { defaults.set(smtpHost, forKey: Keys.smtpHost) }
    }

    var smtpPort: Int {
        didSet { defaults.set(smtpPort, forKey: Keys.smtpPort) }
    }

    var smtpUsername: String {
        didSet { defaults.set(smtpUsername, forKey: Keys.smtpUsername) }
    }

    var smtpFromAddress: String {
        didSet { defaults.set(smtpFromAddress, forKey: Keys.smtpFromAddress) }
    }

    var smtpProviderPreset: SMTPProviderPreset {
        didSet { defaults.set(smtpProviderPreset.rawValue, forKey: Keys.smtpProviderPreset) }
    }

    var isAutomaticEmailConfigured: Bool {
        !smtpHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !smtpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !smtpFromAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && smtpPassword != nil
    }

    var canAutomaticallySendEmail: Bool {
        if useOwnMailServerForEmail {
            return isAutomaticEmailConfigured
        }
        return true
    }

    var selectedPlan: SubscriptionPlan {
        didSet { defaults.set(selectedPlan.rawValue, forKey: Keys.selectedPlan) }
    }

    var hasCompletedPlanSelection: Bool {
        didSet { defaults.set(hasCompletedPlanSelection, forKey: Keys.hasCompletedPlanSelection) }
    }

    var proBackendBaseURL: String {
        didSet { defaults.set(proBackendBaseURL, forKey: Keys.proBackendBaseURL) }
    }

    var platformAPIBaseURL: String {
        didSet { defaults.set(platformAPIBaseURL, forKey: Keys.platformAPIBaseURL) }
    }

    var usePlatformAuth: Bool {
        didSet { defaults.set(usePlatformAuth, forKey: Keys.usePlatformAuth) }
    }

    var exportBrandName: String {
        didSet { defaults.set(exportBrandName, forKey: Keys.exportBrandName) }
    }

    var exportBrandSubtitle: String {
        didSet { defaults.set(exportBrandSubtitle, forKey: Keys.exportBrandSubtitle) }
    }

    /// Auth, usage, and subscription endpoints (Platform when enabled, else notes backend).
    var subscriptionBackendBaseURL: String {
        usePlatformAuth ? platformAPIBaseURL : proBackendBaseURL
    }

    var platformUserID: String? {
        didSet {
            if let platformUserID {
                defaults.set(platformUserID, forKey: Keys.platformUserID)
            } else {
                defaults.removeObject(forKey: Keys.platformUserID)
            }
        }
    }

    var cachedProUsage: ProUsageInfo? {
        get {
            guard let data = defaults.data(forKey: Keys.cachedProUsage) else { return nil }
            return try? JSONDecoder().decode(ProUsageInfo.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.cachedProUsage)
            } else {
                defaults.removeObject(forKey: Keys.cachedProUsage)
            }
        }
    }

    var usesProBackend: Bool {
        if usePlatformAuth {
            return cachedProUsage?.isPro == true
        }
        return selectedPlan == .pro && cachedProUsage?.isPro == true
    }

    var freeVocabularyLimit: Int { 20 }
    static let proAudioRetentionDays = 90

    var effectiveAudioRetentionDays: Int? {
        if usesProBackend {
            return Self.proAudioRetentionDays
        }
        return deleteAudioAfterDays
    }

    func applyProEntitlements() {
        keepAudioFiles = true
        deleteAudioAfterTranscription = false
        if deleteAudioAfterDays == nil {
            deleteAudioAfterDays = Self.proAudioRetentionDays
        }
    }

    var deviceID: String {
        if let existing = keychain.retrieve(for: .deviceID) {
            return existing
        }
        let id = UUID().uuidString
        try? keychain.save(id, for: .deviceID)
        return id
    }
    
    func transcriptionPrompt() -> String? {
        VocabularyFormatter.prompt(from: customVocabulary)
    }
    
    func addVocabularyTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customVocabulary.contains(trimmed) else { return }
        if !usesProBackend, customVocabulary.count >= freeVocabularyLimit {
            return
        }
        customVocabulary = customVocabulary + [trimmed]
    }
    
    func removeVocabularyTerm(_ term: String) {
        customVocabulary = customVocabulary.filter { $0 != term }
    }
    
    init(keychain: KeychainService, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        
        let storedLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.defaultLanguage) ?? "") ?? .luxembourgish
        self.defaultLanguage = storedLanguage.isAutoDetect ? .luxembourgish : storedLanguage
        self.autoDetectLanguage = false
        defaults.set(false, forKey: Keys.autoDetectLanguage)
        self.defaultOutputType = OutputType(rawValue: defaults.string(forKey: Keys.defaultOutputType) ?? "") ?? .meetingNotes
        self.summaryLength = SummaryLength(rawValue: defaults.string(forKey: Keys.summaryLength) ?? "") ?? .detailed
        self.keepAudioFiles = defaults.object(forKey: Keys.keepAudioFiles) as? Bool ?? true
        
        let retentionDays = defaults.integer(forKey: Keys.deleteAudioAfterDays)
        self.deleteAudioAfterDays = retentionDays > 0 ? retentionDays : nil
        
        self.deleteAudioAfterTranscription = defaults.bool(forKey: Keys.deleteAudioAfterTranscription)
        self.emailRecipients = defaults.stringArray(forKey: Keys.emailRecipients) ?? []
        self.emailPolicy = EmailPolicy(rawValue: defaults.string(forKey: Keys.emailPolicy) ?? "") ?? .ask
        self.emailContent = EmailContent(rawValue: defaults.string(forKey: Keys.emailContent) ?? "") ?? .both
        self.emailAttachAudio = defaults.object(forKey: Keys.emailAttachAudio) as? Bool ?? true
        self.emailAttachPDF = defaults.bool(forKey: Keys.emailAttachPDF)
        self.emailAttachMarkdown = defaults.bool(forKey: Keys.emailAttachMarkdown)
        self.faceIDEnabled = defaults.bool(forKey: Keys.faceIDEnabled)
        self.hasAcceptedPrivacyPolicy = defaults.bool(forKey: Keys.hasAcceptedPrivacyPolicy)
        self.consentedProviders = Set(defaults.stringArray(forKey: Keys.consentedProviders) ?? [])
        self.customVocabulary = defaults.stringArray(forKey: Keys.customVocabulary) ?? []
        self.reviewBeforeEmail = defaults.object(forKey: Keys.reviewBeforeEmail) as? Bool ?? true
        if defaults.object(forKey: Keys.sendEmailAfterTranscription) != nil {
            self.sendEmailAfterTranscription = defaults.bool(forKey: Keys.sendEmailAfterTranscription)
        } else {
            let legacyPolicy = EmailPolicy(rawValue: defaults.string(forKey: Keys.emailPolicy) ?? "") ?? .ask
            self.sendEmailAfterTranscription = legacyPolicy == .always
        }
        let storedSMTPHost = defaults.string(forKey: Keys.smtpHost) ?? ""
        self.useOwnMailServerForEmail = defaults.object(forKey: Keys.useOwnMailServerForEmail) != nil
            ? defaults.bool(forKey: Keys.useOwnMailServerForEmail)
            : (!storedSMTPHost.isEmpty && keychain.retrieve(for: .smtpPassword) != nil)
        self.smtpHost = storedSMTPHost
        self.smtpPort = defaults.object(forKey: Keys.smtpPort) as? Int ?? 465
        self.smtpUsername = defaults.string(forKey: Keys.smtpUsername) ?? ""
        self.smtpFromAddress = defaults.string(forKey: Keys.smtpFromAddress) ?? ""
        if let storedPreset = SMTPProviderPreset(rawValue: defaults.string(forKey: Keys.smtpProviderPreset) ?? "") {
            self.smtpProviderPreset = storedPreset
        } else {
            self.smtpProviderPreset = Self.inferredSMTPPreset(host: storedSMTPHost)
        }

        self.selectedPlan = SubscriptionPlan(rawValue: defaults.string(forKey: Keys.selectedPlan) ?? "") ?? .free
        if defaults.object(forKey: Keys.hasCompletedPlanSelection) != nil {
            self.hasCompletedPlanSelection = defaults.bool(forKey: Keys.hasCompletedPlanSelection)
        } else if defaults.bool(forKey: Keys.hasAcceptedPrivacyPolicy) {
            // Existing installs skip plan selection and stay on Free/BYOK.
            self.hasCompletedPlanSelection = true
            self.selectedPlan = .free
        } else {
            self.hasCompletedPlanSelection = false
        }
        self.platformUserID = defaults.string(forKey: Keys.platformUserID)
        self.proBackendBaseURL = defaults.string(forKey: Keys.proBackendBaseURL)
            ?? BackendConfiguration.defaultProBackendURL
        self.platformAPIBaseURL = defaults.string(forKey: Keys.platformAPIBaseURL)
            ?? BackendConfiguration.defaultPlatformAPIURL
        if defaults.object(forKey: Keys.usePlatformAuth) != nil {
            self.usePlatformAuth = defaults.bool(forKey: Keys.usePlatformAuth)
        } else {
            self.usePlatformAuth = BackendConfiguration.usePlatformAuthByDefault
        }
        self.exportBrandName = defaults.string(forKey: Keys.exportBrandName) ?? "Paperorg Notes"
        self.exportBrandSubtitle = defaults.string(forKey: Keys.exportBrandSubtitle) ?? ""
    }
    
    func providerPreferences() -> [AppLanguage: [ProviderID]] {
        guard let data = defaults.data(forKey: Keys.providerPreferences),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return ProviderRegistry.defaultPreferences
        }
        var result: [AppLanguage: [ProviderID]] = [:]
        for (langKey, providerKeys) in decoded {
            if let lang = AppLanguage(rawValue: langKey) {
                result[lang] = providerKeys.compactMap { ProviderID(rawValue: $0) }
            }
        }
        return result.isEmpty ? ProviderRegistry.defaultPreferences : result
    }
    
    func setProviderPreferences(_ prefs: [AppLanguage: [ProviderID]]) {
        var encoded: [String: [String]] = [:]
        for (lang, providers) in prefs {
            encoded[lang.rawValue] = providers.map(\.rawValue)
        }
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Keys.providerPreferences)
        }
    }
    
    func isProviderConsented(_ provider: ProviderID) -> Bool {
        consentedProviders.contains(provider.rawValue)
    }
    
    func consentProvider(_ provider: ProviderID) {
        consentedProviders = consentedProviders.union([provider.rawValue])
    }
    
    func revokeProviderConsent(_ provider: ProviderID) {
        consentedProviders = consentedProviders.subtracting([provider.rawValue])
    }
    
    // MARK: - API Keys
    
    var openAIAPIKey: String? {
        get { keychain.retrieve(for: .openAIAPIKey) }
        set {
            if let newValue, !newValue.isEmpty { try? keychain.save(newValue, for: .openAIAPIKey) }
            else { keychain.delete(for: .openAIAPIKey) }
        }
    }
    
    var elevenLabsAPIKey: String? {
        get { keychain.retrieve(for: .elevenLabsAPIKey) }
        set {
            if let newValue, !newValue.isEmpty { try? keychain.save(newValue, for: .elevenLabsAPIKey) }
            else { keychain.delete(for: .elevenLabsAPIKey) }
        }
    }
    
    var luxASRAPIKey: String? {
        get { keychain.retrieve(for: .luxASRAPIKey) }
        set {
            if let newValue, !newValue.isEmpty { try? keychain.save(newValue, for: .luxASRAPIKey) }
            else { keychain.delete(for: .luxASRAPIKey) }
        }
    }

    var smtpPassword: String? {
        get { keychain.retrieve(for: .smtpPassword) }
        set {
            if let newValue, !newValue.isEmpty { try? keychain.save(newValue, for: .smtpPassword) }
            else { keychain.delete(for: .smtpPassword) }
        }
    }

    func applySMTPPreset(_ preset: SMTPProviderPreset) {
        smtpProviderPreset = preset
        guard let host = preset.smtpHost else { return }
        smtpHost = host
        smtpPort = preset.smtpPort
    }

    private static func inferredSMTPPreset(host: String) -> SMTPProviderPreset {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("outlook") || normalized.contains("office365") {
            return .outlook
        }
        if normalized.contains("gmail") || normalized.contains("google") {
            return .gmail
        }
        if normalized.contains("mail.me.com") || normalized.contains("icloud") {
            return .appleMail
        }
        return normalized.isEmpty ? .appleMail : .custom
    }

    func resetAllData() {
        let domain = Bundle.main.bundleIdentifier ?? ""
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        keychain.deleteAll()
        
        defaultLanguage = .luxembourgish
        autoDetectLanguage = false
        defaultOutputType = .meetingNotes
        summaryLength = .detailed
        keepAudioFiles = true
        deleteAudioAfterDays = nil
        deleteAudioAfterTranscription = false
        emailRecipients = []
        emailPolicy = .ask
        emailContent = .both
        emailAttachAudio = true
        emailAttachPDF = false
        emailAttachMarkdown = false
        faceIDEnabled = false
        hasAcceptedPrivacyPolicy = false
        consentedProviders = []
        customVocabulary = []
        reviewBeforeEmail = true
        sendEmailAfterTranscription = false
        useOwnMailServerForEmail = false
        smtpHost = ""
        smtpPort = 465
        smtpUsername = ""
        smtpFromAddress = ""
        smtpProviderPreset = .appleMail
        smtpPassword = nil
        selectedPlan = .free
        hasCompletedPlanSelection = false
        cachedProUsage = nil
        platformUserID = nil
        usePlatformAuth = BackendConfiguration.usePlatformAuthByDefault
        platformAPIBaseURL = BackendConfiguration.defaultPlatformAPIURL
        proBackendBaseURL = BackendConfiguration.defaultProBackendURL
        exportBrandName = "Paperorg Notes"
        exportBrandSubtitle = ""
        keychain.delete(for: .proAccessToken)
    }
}
