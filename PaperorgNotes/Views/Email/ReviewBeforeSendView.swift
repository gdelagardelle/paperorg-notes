import SwiftUI

struct ReviewBeforeSendView: View {
    @Bindable var note: Note
    let payload: EmailPayload
    let onSend: (EmailPayload) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var editedBody: String
    @State private var editedSubject: String
    
    init(note: Note, payload: EmailPayload, onSend: @escaping (EmailPayload) -> Void) {
        self.note = note
        self.payload = payload
        self.onSend = onSend
        _editedBody = State(initialValue: payload.body)
        _editedSubject = State(initialValue: payload.subject)
    }
    
    private var unclearSegments: [TranscriptSegmentModel] {
        note.segments
            .filter { $0.isUnclear || $0.confidence < 0.6 }
            .sorted { $0.segmentIndex < $1.segmentIndex }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !unclearSegments.isEmpty {
                        reviewWarnings
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Email.subject)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        TextField(L10n.Email.subject, text: $editedSubject)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            }
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Email.message)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        TextEditor(text: $editedBody)
                            .frame(minHeight: 180)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(AppTheme.textPrimary)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            }
                    }
                    
                    if !resolvedAttachments.isEmpty {
                        attachmentSummary
                    }
                    
                    recipientsSummary
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.Email.reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Email.send) {
                        onSend(reviewedPayload)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.light)
    }
    
    private struct ResolvedAttachment: Identifiable {
        let id: String
        let label: String
        let systemImage: String
    }
    
    private var resolvedAttachments: [ResolvedAttachment] {
        var items: [ResolvedAttachment] = []
        if let audioURL = payload.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            items.append(ResolvedAttachment(
                id: "audio",
                label: L10n.Email.attachmentAudio,
                systemImage: "waveform"
            ))
        }
        if let pdfURL = payload.pdfURL,
           FileManager.default.fileExists(atPath: pdfURL.path) {
            items.append(ResolvedAttachment(
                id: "pdf",
                label: L10n.Email.attachmentPDF,
                systemImage: "doc.fill"
            ))
        }
        if let markdownURL = payload.markdownURL,
           FileManager.default.fileExists(atPath: markdownURL.path) {
            items.append(ResolvedAttachment(
                id: "markdown",
                label: L10n.Email.attachmentMarkdown,
                systemImage: "doc.text"
            ))
        }
        return items
    }
    
    private var reviewWarnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.Email.reviewRecommended, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warning)
            
            Text(L10n.Email.reviewWarning(segmentCount: unclearSegments.count))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            
            ForEach(unclearSegments.prefix(5), id: \.id) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    if let speaker = SpeakerLabelFormatter.displayName(for: segment.speakerLabel) {
                        Text(speaker)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.primary)
                    }
                    Text(segment.text)
                        .font(.subheadline)
                    Text(L10n.NoteDetail.segmentConfidence(Int(segment.confidence * 100)))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.unclearHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }
    
    private var attachmentSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Email.attachments)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            
            ForEach(resolvedAttachments) { attachment in
                Label(attachment.label, systemImage: attachment.systemImage)
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
    
    private var recipientsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Email.to)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text(payload.recipients.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
    
    var reviewedPayload: EmailPayload {
        EmailPayload(
            recipients: payload.recipients,
            subject: editedSubject,
            body: editedBody,
            htmlBody: EmailTemplateBuilder.buildHTML(
                content: EmailNoteContent(
                    title: editedSubject,
                    summary: editedBody,
                    transcript: "",
                    contentMode: .summaryOnly,
                    recordedAt: Date(),
                    durationSeconds: 0,
                    language: .english,
                    outputType: .meetingNotes
                )
            ),
            audioURL: payload.audioURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
            pdfURL: payload.pdfURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
            markdownURL: payload.markdownURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        )
    }
}
