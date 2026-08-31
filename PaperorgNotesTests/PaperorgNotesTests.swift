#if APP_CHECK_CLI
import Foundation

@main
struct ProBackendErrorRegression {
    static func main() {
        let rawPayload = #"{"message":"Route POST:/v1/auth/register not found","error":"Not Found","statusCode":404}"#
        guard ProBackendError.serverError(rawPayload).localizedDescription == "Paperorg Pro is temporarily unavailable. Please try again later." else {
            exit(1)
        }
    }
}
#else
import AVFoundation
import XCTest
@testable import PaperorgNotes

final class AudioFileReaderTests: XCTestCase {
    func testMalformedAudioHasZeroPlayableDuration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-invalid-audio-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(AudioTrimService.playableDuration(of: url), 0)
    }

    func testQuietAudioIsAmplifiedForTranscription() throws {
        let sourceURL = try makeAudioFile(amplitude: 0.001)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let originalData = try Data(contentsOf: sourceURL)

        let prepared = try XCTUnwrap(
            AudioFileReader.prepareForTranscription(from: sourceURL)
        )

        XCTAssertGreaterThan(prepared.gainAppliedDecibels, 20)
        XCTAssertLessThanOrEqual(prepared.gainAppliedDecibels, 30)
        XCTAssertEqual(prepared.mimeType, "audio/wav")
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
        XCTAssertGreaterThan(try peakAmplitude(in: prepared.data), 0.01)
    }

    func testNormalAudioIsNotReencoded() throws {
        let sourceURL = try makeAudioFile(amplitude: 0.25)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertNil(try AudioFileReader.prepareForTranscription(from: sourceURL))
    }

    private func makeAudioFile(amplitude: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-audio-test-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        let frameCount: AVAudioFrameCount = 16_000
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = amplitude * sin(2 * .pi * 440 * Float(frame) / 16_000)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func peakAmplitude(in data: Data) throws -> Float {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-prepared-test-\(UUID().uuidString).wav")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        )
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        return (0..<Int(buffer.frameLength)).reduce(Float.zero) {
            max($0, abs(samples[$1]))
        }
    }
}

final class ProviderRegistryTests: XCTestCase {
    @MainActor
    func testLuxembourgishProviderOrder() {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let proBackend = ProBackendClient(settings: settings, keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain, proBackend: proBackend)
        
        let providers = registry.orderedProviders(for: .luxembourgish)
        XCTAssertEqual(providers.first?.identifier, ProviderID.luxasr.rawValue)
        XCTAssertTrue(providers.contains(where: { $0.identifier == ProviderID.elevenlabs.rawValue }))
    }
    
    @MainActor
    func testEnglishIncludesAppleSpeech() {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let proBackend = ProBackendClient(settings: settings, keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain, proBackend: proBackend)
        
        let providers = registry.orderedProviders(for: .english)
        XCTAssertTrue(providers.contains(where: { $0.identifier == ProviderID.apple.rawValue }))
    }
}

final class LocalizationCoverageTests: XCTestCase {
    func testEverySpokenLanguageHasLocalizedStringCatalog() {
        let applicationBundle = Bundle(for: ProviderRegistry.self)
        let supportedCatalogs = Set(applicationBundle.localizations)
        let spokenLanguageCodes = Set(AppLanguage.spokenLanguages.map(\.rawValue))

        XCTAssertTrue(
            spokenLanguageCodes.isSubset(of: supportedCatalogs),
            "Missing UI localization catalogs: \(spokenLanguageCodes.subtracting(supportedCatalogs).sorted().joined(separator: ", "))"
        )
    }
}

final class QualityPipelineTests: XCTestCase {
    @MainActor
    func testFlagsLowConfidenceSegments() async throws {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let proBackend = ProBackendClient(settings: settings, keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain, proBackend: proBackend)
        let orchestrator = TranscriptionOrchestrator(registry: registry)
        let pipeline = QualityPipeline(orchestrator: orchestrator)
        
        let segments = [
            TranscriptSegmentDTO(index: 0, text: "Hello world", startTime: 0, endTime: 2, confidence: 0.9, providerId: "openai"),
            TranscriptSegmentDTO(index: 1, text: "unclear mumble", startTime: 2, endTime: 4, confidence: 0.3, providerId: "openai")
        ]
        
        let result = TranscriptionResult(
            providerId: "openai",
            language: .english,
            segments: segments,
            fullText: "Hello world unclear mumble",
            averageConfidence: 0.6,
            processingTimeMs: 100,
            metadata: [:]
        )
        
        // Use a non-existent audio URL — re-transcription will fail but flagging should work
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        
        let final = try await pipeline.process(
            initialResult: result,
            audioURL: tempURL,
            expectedLanguage: .english
        )
        
        XCTAssertTrue(final.segments.contains(where: { $0.isUnclear }))
        XCTAssertFalse(final.fullText.isEmpty)
    }
    
    @MainActor
    func testDetectsSuspiciousRepeatedCharacters() async throws {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let proBackend = ProBackendClient(settings: settings, keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain, proBackend: proBackend)
        let orchestrator = TranscriptionOrchestrator(registry: registry)
        let pipeline = QualityPipeline(orchestrator: orchestrator)
        
        let segments = [
            TranscriptSegmentDTO(index: 0, text: "aaaaaaa", startTime: 0, endTime: 1, confidence: 0.5, providerId: "openai")
        ]
        
        let result = TranscriptionResult(
            providerId: "openai",
            language: .luxembourgish,
            segments: segments,
            fullText: "aaaaaaa",
            averageConfidence: 0.5,
            processingTimeMs: 100,
            metadata: [:]
        )
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test2.m4a")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        
        let final = try await pipeline.process(
            initialResult: result,
            audioURL: tempURL,
            expectedLanguage: .luxembourgish
        )
        
        XCTAssertFalse(final.qualityReport.suspiciousPhrases.isEmpty)
    }
}

final class SummaryJSONParserTests: XCTestCase {
    func testDecodesCamelCaseSummary() throws {
        let json = """
        {"title":"Team sync","shortSummary":"We discussed launch timing.","detailedSummary":"Detailed notes here.","keyIdeas":[],"decisions":[],"actionItems":[]}
        """.data(using: .utf8)!
        let output = try SummaryJSONParser.decode(json).normalized()
        XCTAssertEqual(output.shortSummary, "We discussed launch timing.")
    }

    func testDecodesSnakeCaseSummary() throws {
        let json = """
        {"title":"Memo","short_summary":"Kuerz Zesummenfassung.","detailed_summary":"Méi laang Zesummenfassung.","key_ideas":["Idee 1"]}
        """.data(using: .utf8)!
        let output = try SummaryJSONParser.decode(json).normalized()
        XCTAssertEqual(output.shortSummary, "Kuerz Zesummenfassung.")
        XCTAssertEqual(output.keyIdeas, ["Idee 1"])
    }

    func testDecodesMarkdownWrappedSummary() throws {
        let json = """
        ```json
        {"shortSummary":"Wrapped summary.","detailedSummary":"Wrapped details."}
        ```
        """.data(using: .utf8)!
        let output = try SummaryJSONParser.decode(json).normalized()
        XCTAssertEqual(output.shortSummary, "Wrapped summary.")
    }
}

final class StructuredOutputTests: XCTestCase {
    func testStructuredOutputEmpty() {
        let output = StructuredOutput.empty(for: .meetingNotes)
        XCTAssertEqual(output.outputType, .meetingNotes)
        XCTAssertTrue(output.actionItems.isEmpty)
    }
}

final class TranscriptTextFormatterTests: XCTestCase {
    func testExtractsTextFromLuxASRJSONArray() {
        let json = """
        [{"speaker":"SPEAKER_00","start":1.2,"end":5.0,"text":"Ech testen dat hei."}]
        """
        let text = TranscriptTextFormatter.readableText(from: json)
        XCTAssertEqual(text, "Ech testen dat hei.")
    }
    
    func testPlainTextPassesThrough() {
        let text = TranscriptTextFormatter.readableText(from: "Hello world")
        XCTAssertEqual(text, "Hello world")
    }
}

final class OfflineTranscriptionRecoveryPolicyTests: XCTestCase {
    func testConnectivityFailuresWaitForNetwork() {
        XCTAssertTrue(
            OfflineTranscriptionRecoveryPolicy.isConnectivityFailure(
                URLError(.notConnectedToInternet)
            )
        )
        XCTAssertTrue(
            OfflineTranscriptionRecoveryPolicy.isConnectivityFailure(
                TranscriptionError.networkError("Connection lost")
            )
        )
    }

    func testProviderFailuresDoNotEnterOfflineQueue() {
        XCTAssertFalse(
            OfflineTranscriptionRecoveryPolicy.isConnectivityFailure(
                TranscriptionError.providerError("Invalid API response")
            )
        )
    }

    func testRetryRequiresConnectivityAudioAndNoInflightWork() {
        XCTAssertTrue(
            OfflineTranscriptionRecoveryPolicy.shouldRetry(
                status: .waitingForNetwork,
                isConnected: true,
                hasAudio: true,
                isInFlight: false
            )
        )
        XCTAssertFalse(
            OfflineTranscriptionRecoveryPolicy.shouldRetry(
                status: .waitingForNetwork,
                isConnected: false,
                hasAudio: true,
                isInFlight: false
            )
        )
        XCTAssertFalse(
            OfflineTranscriptionRecoveryPolicy.shouldRetry(
                status: .waitingForNetwork,
                isConnected: true,
                hasAudio: true,
                isInFlight: true
            )
        )
        XCTAssertFalse(
            OfflineTranscriptionRecoveryPolicy.shouldRetry(
                status: .failed,
                isConnected: true,
                hasAudio: true,
                isInFlight: false
            )
        )
    }
}

final class KeychainServiceTests: XCTestCase {
    func testSaveAndRetrieveAPIKey() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Keychain access is unavailable for the unit test bundle in the simulator.")
        #else
        let keychain = KeychainService()
        keychain.delete(for: .openAIAPIKey)
        try keychain.save("test-key-123", for: .openAIAPIKey)
        XCTAssertEqual(keychain.retrieve(for: .openAIAPIKey), "test-key-123")
        keychain.delete(for: .openAIAPIKey)
        #endif
    }
}

final class LuxASRToggleTests: XCTestCase {
    /// The switch exists so ElevenLabs can be judged on the same recording.
    /// If it does not actually remove LuxASR from the order, the comparison
    /// silently never happens and the toggle is decoration.
    @MainActor
    func testTurningLuxASROffRoutesLuxembourgishPastIt() {
        let settings = SettingsService(keychain: KeychainService(), defaults: Self.scratchDefaults())
        let registry = ProviderRegistry(
            settings: settings,
            keychain: KeychainService(),
            proBackend: ProBackendClient(settings: settings, keychain: KeychainService())
        )

        settings.luxasrEnabled = true
        let withLux = registry.orderedProviders(for: .luxembourgish).map(\.identifier)
        XCTAssertEqual(withLux.first, ProviderID.luxasr.rawValue)

        settings.luxasrEnabled = false
        let withoutLux = registry.orderedProviders(for: .luxembourgish).map(\.identifier)
        XCTAssertFalse(withoutLux.contains(ProviderID.luxasr.rawValue))
        XCTAssertEqual(withoutLux.first, ProviderID.elevenlabs.rawValue)
    }

    @MainActor
    func testOtherLanguagesAreUnaffected() {
        let settings = SettingsService(keychain: KeychainService(), defaults: Self.scratchDefaults())
        let registry = ProviderRegistry(
            settings: settings,
            keychain: KeychainService(),
            proBackend: ProBackendClient(settings: settings, keychain: KeychainService())
        )

        settings.luxasrEnabled = false
        let german = registry.orderedProviders(for: .german).map(\.identifier)
        XCTAssertEqual(german.first, ProviderID.openai.rawValue)
    }

    @MainActor
    func testDefaultsToOnSoShippingBehaviourIsUnchanged() {
        let settings = SettingsService(keychain: KeychainService(), defaults: Self.scratchDefaults())
        XCTAssertTrue(settings.luxasrEnabled)
    }

    private static func scratchDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "luxasr-toggle-\(UUID().uuidString)")!
        return suite
    }
}

final class ProUsageInfoDecodingTests: XCTestCase {
    /// The Platform's /v1/usage carries a `metrics` envelope, which routes the
    /// decoder down a branch that used to hardcode appAttestRequired to false.
    /// A client holding a valid token never re-registers, so that branch was
    /// the only place it could learn attestation had become required -- and it
    /// threw the answer away, so the app sent no attestation and every
    /// recording was refused.
    func testPlatformUsageEnvelopeCarriesTheAttestFlag() throws {
        let json = """
        {
          "app_id": "notes", "period_key": "2026-08", "is_pro": false,
          "pro_expires_at": null, "minutes_limit": 30.0, "minutes_used": 0.0,
          "minutes_remaining": 30.0, "app_attest_required": true,
          "metrics": {"transcription.minutes": {"used": 0.0, "limit": 30.0, "remaining": 30.0}}
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)

        XCTAssertTrue(usage.appAttestRequired)
        XCTAssertEqual(usage.minutesLimit, 30)
        XCTAssertEqual(usage.minutesRemaining, 30.0)
        XCTAssertFalse(usage.isPro)
    }

    func testPlatformUsageEnvelopeWithoutTheFlagStaysFalse() throws {
        let json = """
        {"period_key": "2026-08", "is_pro": false,
         "metrics": {"transcription.minutes": {"used": 0.0, "limit": 30.0, "remaining": 30.0}}}
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)
        XCTAssertFalse(usage.appAttestRequired)
    }

    func testServerErrorDoesNotExposeRawPayloadToUsers() {
        let rawPayload = #"{"message":"Route POST:/v1/auth/register not found","error":"Not Found","statusCode":404}"#
        let message = ProBackendError.serverError(rawPayload).localizedDescription

        XCTAssertEqual(message, "Paperorg Pro is temporarily unavailable. Please try again later.")
    }

    func testDecodesLegacyFlatShape() throws {
        let json = """
        {"is_pro": true, "minutes_limit": 600, "minutes_used": 12.5,
         "minutes_remaining": 587.5, "period_key": "2026-07",
         "pro_expires_at": "2026-08-01T00:00:00Z"}
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)
        XCTAssertTrue(usage.isPro)
        XCTAssertEqual(usage.minutesLimit, 600)
        XCTAssertEqual(usage.minutesUsed, 12.5, accuracy: 0.001)
    }

    func testDecodesPlatformFlatShapeWithFloatLimit() throws {
        // Platform register/refresh usage block: float limit, no expiry field
        let json = """
        {"is_pro": false, "minutes_limit": 600.0, "minutes_used": 0.0,
         "minutes_remaining": 600.0, "period_key": "2026-07"}
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)
        XCTAssertFalse(usage.isPro)
        XCTAssertEqual(usage.minutesLimit, 600)
        XCTAssertNil(usage.proExpiresAt)
    }

    func testDecodesPlatformUsageSummaryEnvelope() throws {
        // Platform GET /v1/usage
        let json = """
        {"app_id": "notes", "period_key": "2026-07",
         "metrics": {"transcription.minutes": {"used": 4.2, "limit": 600.0, "remaining": 595.8}},
         "is_pro": true, "pro_expires_at": null}
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)
        XCTAssertTrue(usage.isPro)
        XCTAssertEqual(usage.minutesLimit, 600)
        XCTAssertEqual(usage.minutesUsed, 4.2, accuracy: 0.001)
        XCTAssertEqual(usage.minutesRemaining, 595.8, accuracy: 0.001)
        XCTAssertEqual(usage.periodKey, "2026-07")
        XCTAssertNil(usage.proExpiresAt)
    }

    @MainActor
    func testIncludedMinutesRouteBackendProcessingWithoutPro() {
        let suiteName = "SettingsServiceIncludedMinutesRoute"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        settings.cachedProUsage = ProUsageInfo(
            isPro: false,
            minutesLimit: 30,
            minutesUsed: 0,
            minutesRemaining: 30,
            periodKey: "2026-08",
            proExpiresAt: nil
        )

        XCTAssertTrue(settings.usesIncludedBackend)
        XCTAssertTrue(settings.usesBackendProcessing)
        XCTAssertFalse(settings.usesProBackend)
    }

    @MainActor
    func testIncludedMinutesUpgradePromptThresholds() {
        let suiteName = "SettingsServiceIncludedMinutesPrompt"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        settings.cachedProUsage = ProUsageInfo(
            isPro: false,
            minutesLimit: 30,
            minutesUsed: 19.9,
            minutesRemaining: 10.1,
            periodKey: "2026-08",
            proExpiresAt: nil
        )

        XCTAssertFalse(settings.shouldSuggestIncludedMinutesUpgrade(afterCompletedNotes: 2))
        XCTAssertTrue(settings.shouldSuggestIncludedMinutesUpgrade(afterCompletedNotes: 3))
        settings.hasSeenIncludedMinutesUpgradePrompt = false
        settings.cachedProUsage = ProUsageInfo(
            isPro: false,
            minutesLimit: 30,
            minutesUsed: 20,
            minutesRemaining: 10,
            periodKey: "2026-08",
            proExpiresAt: nil
        )
        XCTAssertTrue(settings.shouldSuggestIncludedMinutesUpgrade(afterCompletedNotes: 0))
    }
}

@MainActor
final class SubscriptionEntitlementConfirmationTests: XCTestCase {
    func testVerificationFailureDoesNotGrantPro() async {
        let suiteName = "SubscriptionEntitlementConfirmationFailure"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        let service = SubscriptionService(
            settings: settings,
            proBackend: TestSubscriptionVerifier(outcome: .failure)
        )

        let confirmed = await service.confirmSubscription(
            productID: SubscriptionProduct.proMonthly,
            transactionID: "123"
        )

        XCTAssertFalse(confirmed)
        XCTAssertEqual(settings.selectedPlan, .free)
        XCTAssertFalse(service.isProActive)
        XCTAssertEqual(service.lastError, L10n.Subscription.verificationPending)
    }

    func testVerifiedSubscriptionGrantsPro() async {
        let suiteName = "SubscriptionEntitlementConfirmationSuccess"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let usage = ProUsageInfo(
            isPro: true,
            minutesLimit: 600,
            minutesUsed: 0,
            minutesRemaining: 600,
            periodKey: "2026-08",
            proExpiresAt: "2026-09-01T00:00:00Z"
        )
        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        let service = SubscriptionService(
            settings: settings,
            proBackend: TestSubscriptionVerifier(outcome: .success(usage))
        )

        let confirmed = await service.confirmSubscription(
            productID: SubscriptionProduct.proMonthly,
            transactionID: "123"
        )

        XCTAssertTrue(confirmed)
        XCTAssertEqual(settings.selectedPlan, .pro)
        XCTAssertTrue(service.isProActive)
        XCTAssertEqual(service.usageInfo, usage)
        XCTAssertNil(service.lastError)
    }

    func testUnentitledVerificationDoesNotGrantPro() async {
        let suiteName = "SubscriptionEntitlementConfirmationUnentitled"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let usage = ProUsageInfo(
            isPro: false,
            minutesLimit: 30,
            minutesUsed: 0,
            minutesRemaining: 30,
            periodKey: "2026-08",
            proExpiresAt: nil
        )
        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        let service = SubscriptionService(
            settings: settings,
            proBackend: TestSubscriptionVerifier(outcome: .success(usage))
        )

        let confirmed = await service.confirmSubscription(
            productID: SubscriptionProduct.proMonthly,
            transactionID: "123"
        )

        XCTAssertFalse(confirmed)
        XCTAssertEqual(settings.selectedPlan, .free)
        XCTAssertFalse(service.isProActive)
        XCTAssertEqual(service.lastError, L10n.Subscription.entitlementUnavailable)
    }
}

@MainActor
private final class TestSubscriptionVerifier: SubscriptionVerifying {
    enum Outcome {
        case success(ProUsageInfo)
        case failure
    }

    private let outcome: Outcome

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func refreshUsage() async throws -> ProUsageInfo {
        try result()
    }

    func verifySubscription(
        productID: String,
        transactionID: String?,
        signedTransactionInfo: String?
    ) async throws -> ProUsageInfo {
        try result()
    }

    func devActivatePro() async throws -> ProUsageInfo {
        try result()
    }

    private func result() throws -> ProUsageInfo {
        switch outcome {
        case .success(let usage):
            return usage
        case .failure:
            throw ProBackendError.serverError("Verification unavailable")
        }
    }
}

@MainActor
final class AudioImportServiceTests: XCTestCase {
    private var storage: StorageService!
    private var noteId: UUID!

    override func setUp() {
        super.setUp()
        storage = StorageService()
        noteId = UUID()
    }

    override func tearDown() {
        storage.deleteAudio(for: noteId)
        super.tearDown()
    }

    /// Playback, the email attachment and the GDPR export all address audio as
    /// `{noteId}.m4a`, so a WAV has to arrive converted rather than renamed.
    func testWavIsConvertedToM4AAtTheNotesOwnPath() async throws {
        let source = try makeWav(seconds: 3)
        defer { try? FileManager.default.removeItem(at: source) }

        let duration = try await AudioImportService.importAudio(
            from: source,
            noteId: noteId,
            storage: storage,
            maximumMinutes: 180
        )

        XCTAssertEqual(duration, 3, accuracy: 0.1)
        let destination = storage.audioURL(for: noteId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let stored = AVURLAsset(url: destination)
        let storedSeconds = CMTimeGetSeconds(try await stored.load(.duration))
        XCTAssertEqual(storedSeconds, 3, accuracy: 0.2)
        // A copied WAV would still be readable, so assert it was re-encoded.
        let tracks = try await stored.load(.tracks)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(descriptions.first)
        XCTAssertEqual(
            CMFormatDescriptionGetMediaSubType(format),
            kAudioFormatMPEG4AAC
        )
    }

    func testWavConversionShrinksTheUpload() async throws {
        // WAV runs about 10 MB per minute, which the server's 100 MB ceiling cuts
        // off after roughly nine minutes; AAC fits hours into the same budget.
        let source = try makeWav(seconds: 5)
        defer { try? FileManager.default.removeItem(at: source) }
        let originalSize = try Data(contentsOf: source).count

        _ = try await AudioImportService.importAudio(
            from: source,
            noteId: noteId,
            storage: storage,
            maximumMinutes: 180
        )

        let convertedSize = try Data(contentsOf: storage.audioURL(for: noteId)).count
        XCTAssertLessThan(convertedSize, originalSize / 2)
    }

    func testAudioOverTheCapIsRefusedBeforeConverting() async throws {
        let source = try makeWav(seconds: 65)
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await AudioImportService.importAudio(
                from: source,
                noteId: noteId,
                storage: storage,
                maximumMinutes: 1
            )
            XCTFail("a 65-second file was accepted under a one-minute cap")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .tooLong(limitMinutes: 1))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storage.audioURL(for: noteId).path),
            "a refused import left a converted file behind"
        )
    }

    /// The cap arrives from the server, so until it does the server is the only
    /// thing that can refuse an import -- the client must not guess a limit.
    func testAnUnknownCapDoesNotRefuseLocally() async throws {
        let source = try makeWav(seconds: 65)
        defer { try? FileManager.default.removeItem(at: source) }

        let duration = try await AudioImportService.importAudio(
            from: source,
            noteId: noteId,
            storage: storage,
            maximumMinutes: 0
        )

        XCTAssertEqual(duration, 65, accuracy: 0.2)
    }

    func testTooShortAudioIsRefused() async throws {
        let source = try makeWav(seconds: 0.2)
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await AudioImportService.importAudio(
                from: source,
                noteId: noteId,
                storage: storage,
                maximumMinutes: 180
            )
            XCTFail("a 0.2-second file was accepted")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .tooShort)
        }
    }

    /// The file picker filters by type, but a file may still be truncated or
    /// mislabelled, and that has to fail before a note is created for it.
    func testAFileThatIsNotAudioIsRefused() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-not-audio-\(UUID().uuidString).mp3")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: source, options: .atomic)
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await AudioImportService.importAudio(
                from: source,
                noteId: noteId,
                storage: storage,
                maximumMinutes: 180
            )
            XCTFail("four bytes of junk were accepted as audio")
        } catch {
            XCTAssertEqual(error as? AudioImportError, .unreadable)
        }
    }

    /// An M4A is already what the storage layer wants, so re-encoding it would
    /// lose quality for nothing.
    func testM4AIsCopiedRatherThanReencoded() async throws {
        let wav = try makeWav(seconds: 2)
        defer { try? FileManager.default.removeItem(at: wav) }
        _ = try await AudioImportService.importAudio(
            from: wav,
            noteId: noteId,
            storage: storage,
            maximumMinutes: 180
        )
        let existingM4A = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-import-\(UUID().uuidString).m4a")
        try FileManager.default.copyItem(at: storage.audioURL(for: noteId), to: existingM4A)
        defer { try? FileManager.default.removeItem(at: existingM4A) }
        let expected = try Data(contentsOf: existingM4A)

        let secondNote = UUID()
        defer { storage.deleteAudio(for: secondNote) }
        _ = try await AudioImportService.importAudio(
            from: existingM4A,
            noteId: secondNote,
            storage: storage,
            maximumMinutes: 180
        )

        XCTAssertEqual(try Data(contentsOf: storage.audioURL(for: secondNote)), expected)
    }

    func testImportOverwritesAnyEarlierAudioForTheSameNote() async throws {
        let first = try makeWav(seconds: 4)
        let second = try makeWav(seconds: 2)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        _ = try await AudioImportService.importAudio(
            from: first, noteId: noteId, storage: storage, maximumMinutes: 180
        )
        _ = try await AudioImportService.importAudio(
            from: second, noteId: noteId, storage: storage, maximumMinutes: 180
        )

        let stored = AVURLAsset(url: storage.audioURL(for: noteId))
        let seconds = CMTimeGetSeconds(try await stored.load(.duration))
        XCTAssertEqual(seconds, 2, accuracy: 0.2)
    }

    private func makeWav(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-import-source-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        let frameCount = AVAudioFrameCount(seconds * 16_000)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = 0.25 * sin(2 * .pi * 440 * Float(frame) / 16_000)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

final class RecordingLengthCapTests: XCTestCase {
    /// The cap is what lets the app refuse a three-hour import before spending
    /// minutes converting and uploading it, so it has to survive decoding.
    func testUsageCarriesThePerRecordingCap() throws {
        let json = """
        {"is_pro": true, "minutes_limit": 600, "minutes_used": 0.0,
         "minutes_remaining": 600.0, "period_key": "2026-08",
         "max_recording_minutes": 180}
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)

        XCTAssertEqual(usage.maxRecordingMinutes, 180)
    }

    func testPlatformEnvelopeAlsoCarriesTheCap() throws {
        let json = """
        {"period_key": "2026-08", "is_pro": true, "max_recording_minutes": 180,
         "metrics": {"transcription.minutes": {"used": 0.0, "limit": 600.0, "remaining": 600.0}}}
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)

        XCTAssertEqual(usage.maxRecordingMinutes, 180)
    }

    /// A server that predates the cap sends nothing, and a client that invented
    /// a default would refuse imports the server would have accepted.
    func testAnOlderServerLeavesTheCapUnknown() throws {
        let json = """
        {"is_pro": true, "minutes_limit": 600, "minutes_used": 0.0,
         "minutes_remaining": 600.0, "period_key": "2026-08"}
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: json)

        XCTAssertNil(usage.maxRecordingMinutes)
    }

    /// 413 used to fall into serverError, which replaces every message with
    /// "temporarily unavailable" -- telling the user to retry a file that will
    /// be refused every time.
    func testOversizedAudioGetsAnActionableMessage() {
        let message = ProBackendError.audioTooLong.localizedDescription

        XCTAssertNotEqual(
            message,
            "Paperorg Pro is temporarily unavailable. Please try again later."
        )
        XCTAssertFalse(message.isEmpty)
    }
}

/// A 413/429/402 from notes-api is a final answer. Continuing the provider
/// list would reach Apple Speech for English and transcribe without a cap.
final class TranscriptionFallbackPolicyTests: XCTestCase {
    func testQuotaAndIntegrityErrorsStopTheProviderChain() {
        XCTAssertTrue(ProBackendError.audioTooLong.stopsProviderFallback)
        XCTAssertTrue(ProBackendError.usageLimitReached.stopsProviderFallback)
        XCTAssertTrue(ProBackendError.subscriptionRequired.stopsProviderFallback)
        XCTAssertTrue(ProBackendError.deviceIntegrityVerificationFailed.stopsProviderFallback)
    }

    func testTransientBackendErrorsMayTryTheNextProvider() {
        XCTAssertFalse(ProBackendError.serverError("timeout").stopsProviderFallback)
        XCTAssertFalse(ProBackendError.notAuthenticated.stopsProviderFallback)
    }
}

final class RecordingLengthPolicyTests: XCTestCase {
    func testFreeCapStopsAtThreeMinutes() {
        XCTAssertTrue(RecordingLengthPolicy.shouldStop(duration: 180, maxMinutes: 3))
        XCTAssertFalse(RecordingLengthPolicy.shouldStop(duration: 179.9, maxMinutes: 3))
    }

    func testAZeroCapMeansDoNotAutoStop() {
        XCTAssertFalse(RecordingLengthPolicy.shouldStop(duration: 10_000, maxMinutes: 0))
    }

    func testAMissingServerCapStillStopsFreeAtThreeMinutes() {
        XCTAssertEqual(RecordingLengthPolicy.capMinutes(from: nil, isPro: false), 3)
    }

    func testAMissingServerCapStillStopsProAtThreeHours() {
        XCTAssertEqual(RecordingLengthPolicy.capMinutes(from: nil, isPro: true), 180)
    }

    func testTheServerCapWinsWhenPresent() {
        let usage = ProUsageInfo(
            isPro: false,
            minutesLimit: 30,
            minutesUsed: 0,
            minutesRemaining: 30,
            periodKey: "2026-08",
            proExpiresAt: nil,
            maxRecordingMinutes: 10
        )
        XCTAssertEqual(RecordingLengthPolicy.capMinutes(from: usage, isPro: false), 10)
    }
}

final class BackendHTTPMappingTests: XCTestCase {
    func testTranscribeMaps413ToAudioTooLong() {
        let error = ProBackendHTTPMapping.error(
            statusCode: 413,
            message: "payload too large",
            treats413AsAudioTooLong: true
        )
        guard case .audioTooLong = error else {
            return XCTFail("413 on transcribe must be audioTooLong, got \(error)")
        }
    }

    func testEmailMaps413ToAGenericServerError() {
        let error = ProBackendHTTPMapping.error(
            statusCode: 413,
            message: "payload too large",
            treats413AsAudioTooLong: false
        )
        guard case .serverError = error else {
            return XCTFail("413 on email must not claim the audio is too long, got \(error)")
        }
    }
}

final class ImportPickerCancelTests: XCTestCase {
    func testACancelledPickerHasNoUserFacingError() {
        let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        XCTAssertNil(ImportPickerResult.userFacingError(from: cancelled))
        XCTAssertNil(ImportPickerResult.userFacingError(from: CancellationError()))
    }

    func testARealPickerFailureStillSurfaces() {
        let failed = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [NSLocalizedDescriptionKey: "missing"]
        )
        XCTAssertEqual(ImportPickerResult.userFacingError(from: failed), "missing")
    }
}
#endif
