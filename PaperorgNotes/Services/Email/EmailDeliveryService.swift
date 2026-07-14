import Foundation

@MainActor
final class EmailDeliveryService {
    private let settings: SettingsService
    private let backend: ProBackendClient
    private let smtp: SMTPEmailDeliveryService

    init(settings: SettingsService, backend: ProBackendClient, smtp: SMTPEmailDeliveryService) {
        self.settings = settings
        self.backend = backend
        self.smtp = smtp
    }

    func send(_ payload: EmailPayload) async throws {
        if settings.useOwnMailServerForEmail {
            try await smtp.send(payload)
        } else {
            try await backend.sendEmail(payload)
        }
    }
}
