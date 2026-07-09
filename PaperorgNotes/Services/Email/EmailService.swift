import Foundation

enum EmailError: LocalizedError {
    case noRecipients
    case disabled
    case emptyContent
    case mailNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .noRecipients:
            return "Add at least one email address in Settings → Email."
        case .disabled:
            return "Email sending is disabled. Change the policy in Settings → Email."
        case .emptyContent:
            return "Nothing to send yet — wait for transcription to finish."
        case .mailNotAvailable:
            return "Mail is not configured on this device. Use the share option instead."
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
        guard settings.emailPolicy != .never else { throw EmailError.disabled }
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
        
        if settings.emailAttachAudio && note.audioDeletedAt == nil {
            audioURL = exportService.audioURL(for: note)
        }
        
        if settings.emailAttachPDF {
            pdfURL = try? exportService.exportPDF(note: note)
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
    
    var shouldAutoPrepare: Bool {
        settings.emailPolicy == .always && !settings.emailRecipients.isEmpty
    }
    
    var shouldAskBeforeSend: Bool {
        settings.emailPolicy == .ask && !settings.emailRecipients.isEmpty
    }
}
