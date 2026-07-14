import Foundation

enum EmailError: LocalizedError, Equatable {
    case noRecipients
    case disabled
    case emptyContent
    case mailNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .noRecipients:
            return String(localized: "email.error.no_recipients")
        case .disabled:
            return String(localized: "email.error.disabled")
        case .emptyContent:
            return String(localized: "email.error.empty_content")
        case .mailNotAvailable:
            return String(localized: "email.error.mail_not_available")
        }
    }
}

@MainActor
final class EmailService {
    private let settings: SettingsService
    
    init(settings: SettingsService) {
        self.settings = settings
    }
    
    func buildPayload(for note: Note, exportService: ExportService) throws -> EmailPayload {
        guard !settings.emailRecipients.isEmpty else { throw EmailError.noRecipients }
        
        let subject = note.title
        var body = ""
        
        switch settings.emailContent {
        case .summaryOnly:
            body = note.displaySummaryShort
        case .fullTranscript:
            body = note.displayTranscript
        case .both:
            body = """
            SUMMARY
            \(note.displaySummaryShort)
            
            ---
            
            TRANSCRIPT
            \(note.displayTranscript)
            """
        }
        
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmailError.emptyContent
        }
        
        var audioURL: URL?
        var pdfURL: URL?
        var markdownURL: URL?
        
        if settings.emailAttachAudio && note.audioDeletedAt == nil,
           let candidate = exportService.audioURL(for: note),
           FileManager.default.fileExists(atPath: candidate.path) {
            audioURL = candidate
        }
        
        if settings.emailAttachPDF {
            pdfURL = try? exportService.exportPDF(
                note: note,
                branding: ExportBranding.from(settings: settings, storage: exportService.storage)
            )
        }
        
        if settings.emailAttachMarkdown {
            markdownURL = try? exportService.exportMarkdown(note: note)
        }
        
        return EmailPayload(
            recipients: settings.emailRecipients,
            subject: subject,
            body: body,
            audioURL: audioURL,
            pdfURL: pdfURL,
            markdownURL: markdownURL
        )
    }
    
    var shouldSendAfterTranscription: Bool {
        settings.sendEmailAfterTranscription
            && !settings.emailRecipients.isEmpty
            && settings.isAutomaticEmailConfigured
    }
}
