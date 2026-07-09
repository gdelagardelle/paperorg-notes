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
                        Text("Subject")
                            .font(.headline)
                        TextField("Subject", text: $editedSubject)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.headline)
                        TextEditor(text: $editedBody)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    attachmentSummary
                    
                    recipientsSummary
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Review before send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(reviewedPayload)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var reviewWarnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Review recommended", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.warning)
            
            Text("\(unclearSegments.count) segment(s) have low confidence. Check the transcript before sending.")
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
                    Text("\(Int(segment.confidence * 100))% confidence")
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
            Text("Attachments")
                .font(.headline)
            
            if payload.audioURL != nil {
                Label("Audio file", systemImage: "waveform")
            }
            if payload.pdfURL != nil {
                Label("PDF", systemImage: "doc.fill")
            }
            if payload.markdownURL != nil {
                Label("Markdown", systemImage: "doc.text")
            }
            if payload.audioURL == nil && payload.pdfURL == nil && payload.markdownURL == nil {
                Text("None")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .font(.subheadline)
        .cardStyle()
    }
    
    private var recipientsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To")
                .font(.headline)
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
            audioURL: payload.audioURL,
            pdfURL: payload.pdfURL,
            markdownURL: payload.markdownURL
        )
    }
}
