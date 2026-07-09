import Foundation

@MainActor
final class EmailService {
    private let settings: SettingsService
    
    init(settings: SettingsService) {
        self.settings = settings
    }
    
    func buildPayload(for note: Note, exportService: ExportService) throws -> EmailPayload? {
        guard !settings.emailRecipients.isEmpty else { return nil }
        guard settings.emailPolicy != .never else { return nil }
        
        let subject = note.title
        var body = ""
        
        switch settings.emailContent {
        case .summaryOnly:
            body = note.summaryShort ?? note.summaryDetailed ?? ""
        case .fullTranscript:
            body = note.displayTranscript
        case .both:
            body = """
            SUMMARY
            \(note.summaryShort ?? "")
            
            ---
            
            TRANSCRIPT
            \(note.displayTranscript)
            """
        }
        
        var audioURL: URL?
        var pdfURL: URL?
        var markdownURL: URL?
        
        if settings.emailAttachAudio && note.audioDeletedAt == nil {
            audioURL = exportService.storage.audioURL(for: note.id)
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
}
