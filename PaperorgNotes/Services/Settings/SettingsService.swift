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
    
    func transcriptionPrompt() -> String? {
        VocabularyFormatter.prompt(from: customVocabulary)
    }
    
    func addVocabularyTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customVocabulary.contains(trimmed) else { return }
        customVocabulary = customVocabulary + [trimmed]
    }
    
    func removeVocabularyTerm(_ term: String) {
        customVocabulary = customVocabulary.filter { $0 != term }
    }
    
    init(keychain: KeychainService, defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        
        self.defaultLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.defaultLanguage) ?? "") ?? .luxembourgish
        self.autoDetectLanguage = defaults.object(forKey: Keys.autoDetectLanguage) as? Bool ?? true
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
    
    func resetAllData() {
        let domain = Bundle.main.bundleIdentifier ?? ""
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        keychain.deleteAll()
        
        defaultLanguage = .luxembourgish
        autoDetectLanguage = true
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
    }
}
