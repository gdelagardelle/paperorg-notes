import XCTest
@testable import PaperorgNotes

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
}
