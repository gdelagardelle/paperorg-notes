import Foundation

struct TranscriptionCredentials: Sendable {
    let openAIAPIKey: String?
    let elevenLabsAPIKey: String?
    let luxASRAPIKey: String?
    
    @MainActor
    static func from(_ settings: SettingsService) -> TranscriptionCredentials {
        TranscriptionCredentials(
            openAIAPIKey: nil,
            elevenLabsAPIKey: nil,
            luxASRAPIKey: nil
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
    let proBackend: ProBackendClient
    private let providers: [String: any TranscriptionProvider]
    
    init(settings: SettingsService, keychain: KeychainService, proBackend: ProBackendClient) {
        self.settings = settings
        self.proBackend = proBackend
        self.providers = [
            ProviderID.luxasr.rawValue: LuxASRProvider(),
            ProviderID.openai.rawValue: OpenAITranscriptionProvider(),
            ProviderID.elevenlabs.rawValue: ElevenLabsScribeProvider(),
            ProviderID.apple.rawValue: AppleSpeechProvider()
        ]
    }
    
    func orderedProviders(for language: AppLanguage) -> [any TranscriptionProvider] {
        if language.isAutoDetect {
            let order: [ProviderID] = [.openai, .elevenlabs]
            return order.compactMap { providers[$0.rawValue] }
        }

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
    private let proRouter: ProTranscriptionRouter
    
    init(registry: ProviderRegistry) {
        self.registry = registry
        self.proRouter = ProTranscriptionRouter(registry: registry)
    }
    
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard registry.settings.usesBackendProcessing else {
            throw ProBackendError.subscriptionRequired
        }
        return try await proRouter.transcribe(request)
    }
    
    func retranscribeSegment(
        request: TranscriptionRequest,
        excludingProvider: String
    ) async throws -> TranscriptionResult {
        guard registry.settings.usesBackendProcessing else {
            throw ProBackendError.subscriptionRequired
        }
        return try await proRouter.transcribe(request)
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
