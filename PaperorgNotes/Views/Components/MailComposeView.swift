import SwiftUI
import MessageUI
import UIKit

final class EmailActivityItem: NSObject, UIActivityItemSource {
    let subject: String
    let body: String

    init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        body
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        body
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}

extension EmailPayload {
    var shareTextBody: String {
        guard !recipients.isEmpty else { return body }
        return "To: \(recipients.joined(separator: ", "))\n\n\(body)"
    }

    func shareItems() -> [Any] {
        var items: [Any] = [EmailActivityItem(subject: subject, body: shareTextBody)]
        if let audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            items.append(audioURL)
        }
        if let pdfURL {
            items.append(pdfURL)
        }
        if let markdownURL {
            items.append(markdownURL)
        }
        return items
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let payload: EmailPayload
    @Environment(\.dismiss) private var dismiss
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(payload.recipients)
        vc.setSubject(payload.subject)
        vc.setMessageBody(payload.body, isHTML: false)
        
        if let audioURL = payload.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path),
           let data = try? Data(contentsOf: audioURL) {
            vc.addAttachmentData(data, mimeType: "audio/m4a", fileName: audioURL.lastPathComponent)
        }
        if let pdfURL = payload.pdfURL,
           let data = try? Data(contentsOf: pdfURL) {
            vc.addAttachmentData(data, mimeType: "application/pdf", fileName: pdfURL.lastPathComponent)
        }
        if let mdURL = payload.markdownURL,
           let data = try? Data(contentsOf: mdURL) {
            vc.addAttachmentData(data, mimeType: "text/markdown", fileName: mdURL.lastPathComponent)
        }
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EmailComposeSheet: View {
    let payload: EmailPayload

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposeView(payload: payload)
        } else {
            ActivityShareSheet(items: payload.shareItems())
        }
    }
}

struct EmailButton: View {
    let note: Note
    @Environment(AppEnvironment.self) private var environment
    @State private var presentation: EmailPresentation?
    @State private var emailError: EmailError?
    
    private var shouldReviewFirst: Bool {
        environment.settingsService.reviewBeforeEmail
            || note.segments.contains { $0.isUnclear || $0.confidence < 0.6 }
    }
    
    var body: some View {
        Button(L10n.Email.button) {
            sendEmail()
        }
        .buttonStyle(PrimaryButtonStyle())
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .review(let payload, _):
                ReviewBeforeSendView(note: note, payload: payload) { reviewed in
                    self.presentation = .compose(reviewed, UUID())
                }
            case .compose(let payload, _):
                EmailComposeSheet(payload: payload)
            }
        }
        .alert(L10n.Email.alertTitle, isPresented: Binding(
            get: { emailError != nil },
            set: { if !$0 { emailError = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
            if emailError == .noRecipients {
                Button(L10n.Email.openSettings) {
                    emailError = nil
                    environment.deepLinkHandler.selectedTab = 3
                }
            }
        } message: {
            Text(emailError?.localizedDescription ?? "")
        }
    }
    
    func sendEmail() {
        do {
            let payload = try environment.emailService.buildPayload(
                for: note,
                exportService: environment.exportService
            )
            if shouldReviewFirst {
                presentation = .review(payload, UUID())
            } else {
                presentation = .compose(payload, UUID())
            }
        } catch {
            if let error = error as? EmailError {
                emailError = error
            }
        }
    }
}

enum EmailPresentation: Identifiable {
    case review(EmailPayload, UUID)
    case compose(EmailPayload, UUID)

    var id: UUID {
        switch self {
        case .review(_, let id), .compose(_, let id):
            return id
        }
    }
}
