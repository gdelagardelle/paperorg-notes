import Foundation

struct TranscriptionCredentials: Sendable {
    let openAIAPIKey: String?
    let elevenLabsAPIKey: String?
    let luxASRAPIKey: String?
    
    @MainActor
    static func from(_ settings: SettingsService) -> TranscriptionCredentials {
        TranscriptionCredentials(
            openAIAPIKey: settings.openAIAPIKey,
            elevenLabsAPIKey: settings.elevenLabsAPIKey,
            luxASRAPIKey: settings.luxASRAPIKey
        )
    }
}

protocol TranscriptionProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var supportedLanguages: Set<AppLanguage> { get }
    var requiresNetwork: Bool { get }
    var sendsAudioOffDevice: Bool { get }
    var supportsDiarization: Bool { get }
    var supportsWordTimestamps: Bool { get }
    
    func isConfigured(credentials: TranscriptionCredentials) -> Bool
    func transcribe(_ request: TranscriptionRequest, credentials: TranscriptionCredentials) async throws -> TranscriptionResult
}

extension TranscriptionProvider {
    var requiresNetwork: Bool { true }
    var sendsAudioOffDevice: Bool { true }
}

@MainActor
final class ProviderRegistry {
    static let defaultPreferences: [AppLanguage: [ProviderID]] = [
        .luxembourgish: [.luxasr, .elevenlabs, .openai],
        .german: [.openai, .elevenlabs],
        .french: [.openai, .elevenlabs],
        .english: [.openai, .apple, .elevenlabs],
        .portuguese: [.openai, .elevenlabs]
    ]
    
    let settings: SettingsService
    private let providers: [String: any TranscriptionProvider]
    
    init(settings: SettingsService, keychain: KeychainService) {
        self.settings = settings
        self.providers = [
            ProviderID.luxasr.rawValue: LuxASRProvider(),
            ProviderID.openai.rawValue: OpenAITranscriptionProvider(),
            ProviderID.elevenlabs.rawValue: ElevenLabsScribeProvider(),
            ProviderID.apple.rawValue: AppleSpeechProvider()
        ]
    }
    
    func orderedProviders(for language: AppLanguage) -> [any TranscriptionProvider] {
        let prefs = settings.providerPreferences()
        let order = prefs[language] ?? Self.defaultPreferences[language] ?? [.openai]
        return order.compactMap { providers[$0.rawValue] }
            .filter { $0.supportedLanguages.contains(language) }
    }
    
    func provider(for id: ProviderID) -> (any TranscriptionProvider)? {
        providers[id.rawValue]
    }
}

@MainActor
final class TranscriptionOrchestrator {
    let registry: ProviderRegistry
    
    init(registry: ProviderRegistry) {
        self.registry = registry
    }
    
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let providers = registry.orderedProviders(for: request.language)
        guard !providers.isEmpty else {
            throw TranscriptionError.noProviderAvailable(request.language)
        }
        
        var lastError: Error?
        let credentials = TranscriptionCredentials.from(registry.settings)
        
        for provider in providers {
            guard let providerId = ProviderID(rawValue: provider.identifier) else { continue }
            
            if provider.sendsAudioOffDevice && !registry.settings.isProviderConsented(providerId) {
                lastError = TranscriptionError.providerNotConsented(providerId)
                continue
            }
            
            guard provider.isConfigured(credentials: credentials) else {
                lastError = TranscriptionError.missingAPIKey(providerId)
                continue
            }
            
            do {
                let result = try await provider.transcribe(request, credentials: credentials)
                guard !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranscriptionError.emptyResult
                }
                return result
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? TranscriptionError.noProviderAvailable(request.language)
    }
    
    func retranscribeSegment(
        request: TranscriptionRequest,
        excludingProvider: String
    ) async throws -> TranscriptionResult {
        let providers = registry.orderedProviders(for: request.language)
            .filter { $0.identifier != excludingProvider }
        
        let credentials = TranscriptionCredentials.from(registry.settings)
        
        for provider in providers {
            guard provider.isConfigured(credentials: credentials) else { continue }
            do {
                return try await provider.transcribe(request, credentials: credentials)
            } catch { continue }
        }
        throw TranscriptionError.noProviderAvailable(request.language)
    }
}

@MainActor
final class TranscriptionService {
    private let orchestrator: TranscriptionOrchestrator
    
    init(orchestrator: TranscriptionOrchestrator) {
        self.orchestrator = orchestrator
    }
    
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try await orchestrator.transcribe(request)
    }
}
