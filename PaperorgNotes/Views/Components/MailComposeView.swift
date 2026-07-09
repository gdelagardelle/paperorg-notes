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
    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [Any] = []
    @State private var showShareFallback = false
    
    var body: some View {
        Group {
            if MFMailComposeViewController.canSendMail() {
                MailComposeView(payload: payload)
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.warning)
                        
                        Text("Mail Not Configured")
                            .font(.title3.bold())
                        
                        Text("No Mail account is set up on this device. You can share the note by email or another app instead.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Share Note") {
                            shareItems = buildShareItems()
                            showShareFallback = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal)
                    }
                    .padding()
                    .navigationTitle("Send Email")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareFallback) {
            ActivityShareSheet(items: shareItems)
        }
    }
    
    private func buildShareItems() -> [Any] {
        var items: [Any] = [payload.body]
        if let audioURL = payload.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            items.append(audioURL)
        }
        if let pdfURL = payload.pdfURL {
            items.append(pdfURL)
        }
        if let markdownURL = payload.markdownURL {
            items.append(markdownURL)
        }
        return items
    }
}

struct EmailButton: View {
    let note: Note
    @Environment(AppEnvironment.self) private var environment
    @State private var mailPayload: EmailPayload?
    @State private var showMail = false
    @State private var showReview = false
    @State private var alertMessage: String?
    
    private var shouldReviewFirst: Bool {
        environment.settingsService.reviewBeforeEmail
            || note.segments.contains { $0.isUnclear || $0.confidence < 0.6 }
    }
    
    var body: some View {
        Button("Email") {
            sendEmail()
        }
        .buttonStyle(PrimaryButtonStyle())
        .sheet(isPresented: $showReview) {
            if let payload = mailPayload {
                ReviewBeforeSendView(note: note, payload: payload) { reviewed in
                    mailPayload = reviewed
                    showMail = true
                }
            }
        }
        .sheet(isPresented: $showMail) {
            if let payload = mailPayload {
                EmailComposeSheet(payload: payload)
            }
        }
        .alert("Email", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
            if alertMessage == EmailError.noRecipients.localizedDescription {
                Button("Open Settings") {
                    // Tab switching handled by parent if needed
                }
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }
    
    func sendEmail() {
        do {
            let payload = try environment.emailService.buildPayload(
                for: note,
                exportService: environment.exportService
            )
            mailPayload = payload
            if shouldReviewFirst {
                showReview = true
            } else {
                showMail = true
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
