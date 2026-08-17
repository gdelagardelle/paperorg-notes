import Foundation
import Network
import SwiftUI

@Observable
@MainActor
final class ConnectivityMonitor {
    private(set) var isConnected = false
    @ObservationIgnored private let monitor: NWPathMonitor
    @ObservationIgnored private let queue = DispatchQueue(label: "com.paperorg.notes.connectivity")

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = isConnected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

@Observable
@MainActor
final class AppEnvironment {
    let recordingService: RecordingService
    let transcriptionService: TranscriptionService
    let summaryService: SummaryService
    let storageService: StorageService
    let settingsService: SettingsService
    let emailService: EmailService
    let smtpEmailDeliveryService: SMTPEmailDeliveryService
    let emailDeliveryService: EmailDeliveryService
    let exportService: ExportService
    let qualityPipeline: QualityPipeline
    let keychainService: KeychainService
    let processRecordingUseCase: ProcessRecordingUseCase
    let deleteNoteUseCase: DeleteNoteUseCase
    let deepLinkHandler: DeepLinkHandler
    let proBackendClient: ProBackendClient
    let subscriptionService: SubscriptionService
    let connectivityMonitor: ConnectivityMonitor
    
    init(
        recordingService: RecordingService,
        transcriptionService: TranscriptionService,
        summaryService: SummaryService,
        storageService: StorageService,
        settingsService: SettingsService,
        emailService: EmailService,
        smtpEmailDeliveryService: SMTPEmailDeliveryService,
        emailDeliveryService: EmailDeliveryService,
        exportService: ExportService,
        qualityPipeline: QualityPipeline,
        keychainService: KeychainService,
        deepLinkHandler: DeepLinkHandler,
        proBackendClient: ProBackendClient,
        subscriptionService: SubscriptionService,
        connectivityMonitor: ConnectivityMonitor? = nil
    ) {
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
        self.storageService = storageService
        self.settingsService = settingsService
        self.emailService = emailService
        self.smtpEmailDeliveryService = smtpEmailDeliveryService
        self.emailDeliveryService = emailDeliveryService
        self.exportService = exportService
        self.qualityPipeline = qualityPipeline
        self.keychainService = keychainService
        self.deepLinkHandler = deepLinkHandler
        self.proBackendClient = proBackendClient
        self.subscriptionService = subscriptionService
        self.connectivityMonitor = connectivityMonitor ?? ConnectivityMonitor()
        self.processRecordingUseCase = ProcessRecordingUseCase(
            transcriptionService: transcriptionService,
            summaryService: summaryService,
            storageService: storageService,
            qualityPipeline: qualityPipeline,
            settingsService: settingsService
        )
        self.deleteNoteUseCase = DeleteNoteUseCase(storageService: storageService)
    }
    
    static let live: AppEnvironment = {
        let keychain = KeychainService()
        let settings = SettingsService(keychain: keychain)
        let storage = StorageService()
        let proBackend = ProBackendClient(settings: settings, keychain: keychain)
        let subscription = SubscriptionService(settings: settings, proBackend: proBackend)
        let registry = ProviderRegistry(settings: settings, keychain: keychain, proBackend: proBackend)
        let orchestrator = TranscriptionOrchestrator(registry: registry)
        let transcription = TranscriptionService(orchestrator: orchestrator)
        let summary = SummaryService(settings: settings, keychain: keychain, proBackend: proBackend)
        let recording = RecordingService(storage: storage)
        let email = EmailService(settings: settings)
        let smtpEmail = SMTPEmailDeliveryService(settings: settings)
        let emailDelivery = EmailDeliveryService(settings: settings, backend: proBackend, smtp: smtpEmail)
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
            smtpEmailDeliveryService: smtpEmail,
            emailDeliveryService: emailDelivery,
            exportService: export,
            qualityPipeline: quality,
            keychainService: keychain,
            deepLinkHandler: deepLink,
            proBackendClient: proBackend,
            subscriptionService: subscription
        )
    }()
}
