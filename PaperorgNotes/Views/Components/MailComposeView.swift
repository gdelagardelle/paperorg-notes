import SwiftUI
import MessageUI

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

struct MailComposeWrapper: View {
    let payload: EmailPayload
    
    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposeView(payload: payload)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "envelope.badge.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.warning)
                Text("Mail Not Configured")
                    .font(.headline)
                Text("Set up a Mail account on this device to send transcripts.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
