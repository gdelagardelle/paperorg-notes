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

final class ProUsageInfoDecodingTests: XCTestCase {
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
#endif
