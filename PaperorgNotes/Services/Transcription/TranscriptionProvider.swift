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
        if registry.settings.usesProBackend {
            return try await proRouter.transcribe(request)
        }

        let providers = registry.orderedProviders(for: request.language)
        guard !providers.isEmpty else {
            throw TranscriptionError.noProviderAvailable(request.language)
        }
        
        var lastError: Error?
        var attemptLog: [String] = []
        let credentials = TranscriptionCredentials.from(registry.settings)
        
        for provider in providers {
            guard let providerId = ProviderID(rawValue: provider.identifier) else { continue }
            
            if provider.sendsAudioOffDevice && !registry.settings.isProviderConsented(providerId) {
                lastError = TranscriptionError.providerNotConsented(providerId)
                attemptLog.append("\(provider.identifier): skipped — consent missing")
                continue
            }
            
            guard provider.isConfigured(credentials: credentials) else {
                lastError = TranscriptionError.missingAPIKey(providerId)
                attemptLog.append("\(provider.identifier): skipped — API key missing")
                continue
            }
            
            let startedAt = Date()
            do {
                let result = try await provider.transcribe(request, credentials: credentials)
                guard !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranscriptionError.emptyResult
                }
                attemptLog.append("\(provider.identifier): succeeded in \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s")
                var metadata = result.metadata
                metadata["attemptLog"] = attemptLog.joined(separator: " | ")
                return TranscriptionResult(
                    providerId: result.providerId,
                    language: result.language,
                    segments: result.segments,
                    fullText: result.fullText,
                    averageConfidence: result.averageConfidence,
                    processingTimeMs: result.processingTimeMs,
                    metadata: metadata
                )
            } catch {
                lastError = error
                attemptLog.append("\(provider.identifier): failed after \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s — \(error.localizedDescription)")
                continue
            }
        }
        
        throw lastError ?? TranscriptionError.noProviderAvailable(request.language)
    }
    
    func retranscribeSegment(
        request: TranscriptionRequest,
        excludingProvider: String
    ) async throws -> TranscriptionResult {
        if registry.settings.usesProBackend {
            return try await proRouter.transcribe(request)
        }

        let providers = registry.orderedProviders(for: request.language)
            .filter { $0.identifier != excludingProvider }
        
        let credentials = TranscriptionCredentials.from(registry.settings)
        
        for provider in providers {
            guard let providerId = ProviderID(rawValue: provider.identifier) else { continue }
            guard !provider.sendsAudioOffDevice || registry.settings.isProviderConsented(providerId) else {
                continue
            }
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
