import XCTest
@testable import PaperorgNotes

final class ProviderRegistryTests: XCTestCase {
    @MainActor
    func testLuxembourgishProviderOrder() {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain)
        
        let providers = registry.orderedProviders(for: .luxembourgish)
        XCTAssertEqual(providers.first?.identifier, ProviderID.luxasr.rawValue)
        XCTAssertTrue(providers.contains(where: { $0.identifier == ProviderID.elevenlabs.rawValue }))
    }
    
    @MainActor
    func testEnglishIncludesAppleSpeech() {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain)
        
        let providers = registry.orderedProviders(for: .english)
        XCTAssertTrue(providers.contains(where: { $0.identifier == ProviderID.apple.rawValue }))
    }
}

final class QualityPipelineTests: XCTestCase {
    @MainActor
    func testFlagsLowConfidenceSegments() async throws {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let registry = ProviderRegistry(settings: settings, keychain: keychain)
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
        let registry = ProviderRegistry(settings: settings, keychain: keychain)
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

final class KeychainServiceTests: XCTestCase {
    func testSaveAndRetrieveAPIKey() throws {
        let keychain = KeychainService()
        keychain.delete(for: .openAIAPIKey)
        try keychain.save("test-key-123", for: .openAIAPIKey)
        XCTAssertEqual(keychain.retrieve(for: .openAIAPIKey), "test-key-123")
        keychain.delete(for: .openAIAPIKey)
    }
}
