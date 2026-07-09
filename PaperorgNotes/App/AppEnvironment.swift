import Foundation
import SwiftUI

@Observable
@MainActor
final class AppEnvironment {
    let recordingService: RecordingService
    let transcriptionService: TranscriptionService
    let summaryService: SummaryService
    let storageService: StorageService
    let settingsService: SettingsService
    let emailService: EmailService
    let exportService: ExportService
    let qualityPipeline: QualityPipeline
    let keychainService: KeychainService
    let processRecordingUseCase: ProcessRecordingUseCase
    let deepLinkHandler: DeepLinkHandler
    
    init(
        recordingService: RecordingService,
        transcriptionService: TranscriptionService,
        summaryService: SummaryService,
        storageService: StorageService,
        settingsService: SettingsService,
        emailService: EmailService,
        exportService: ExportService,
        qualityPipeline: QualityPipeline,
        keychainService: KeychainService,
        deepLinkHandler: DeepLinkHandler
    ) {
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
        self.storageService = storageService
        self.settingsService = settingsService
        self.emailService = emailService
        self.exportService = exportService
        self.qualityPipeline = qualityPipeline
        self.keychainService = keychainService
        self.deepLinkHandler = deepLinkHandler
        self.processRecordingUseCase = ProcessRecordingUseCase(
            transcriptionService: transcriptionService,
            summaryService: summaryService,
            storageService: storageService,
            qualityPipeline: qualityPipeline,
            settingsService: settingsService
        )
    }
    
    static let live: AppEnvironment = {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let storage = StorageService()
        let registry = ProviderRegistry(settings: settings, keychain: keychain)
        let orchestrator = TranscriptionOrchestrator(registry: registry)
        let transcription = TranscriptionService(orchestrator: orchestrator)
        let summary = SummaryService(settings: settings, keychain: keychain)
        let recording = RecordingService(storage: storage)
        let email = EmailService(settings: settings)
        let export = ExportService(storage: storage)
        let quality = QualityPipeline(orchestrator: orchestrator)
        let deepLink = DeepLinkHandler()
        
        return AppEnvironment(
            recordingService: recording,
            transcriptionService: transcription,
            summaryService: summary,
            storageService: storage,
            settingsService: settings,
            emailService: email,
            exportService: export,
            qualityPipeline: quality,
            keychainService: keychain,
            deepLinkHandler: deepLink
        )
    }()
}
