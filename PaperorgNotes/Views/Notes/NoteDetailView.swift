import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note
    
    @State private var selectedTab = 0
    @State private var selectedOutputType: OutputType = .meetingNotes
    @State private var selectedLanguage: AppLanguage = .luxembourgish
    @State private var isProcessing = false
    @State private var processingStage: ProcessingStage = .transcribing
    @State private var processingError: String?
    @State private var editingSegment: TranscriptSegmentModel?
    @State private var editText = ""
    @StateObject private var playback = AudioPlaybackService()
    
    private var audioAvailable: Bool {
        FileManager.default.fileExists(atPath: environment.storageService.audioURL(for: note.id).path)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataHeader
                NoteOrganizerSection(note: note)
                reprocessSection
                tabPicker
                tabContent
                actionButtons
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedOutputType = note.noteOutputType
            selectedLanguage = note.appLanguage
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleFavorite) {
                    Image(systemName: note.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(note.isFavorite ? AppTheme.warning : AppTheme.textSecondary)
                }
            }
        }
        .sheet(item: $editingSegment) { segment in
            segmentEditSheet(segment)
        }
        .sheet(isPresented: $isProcessing) {
            ProcessingView(
                stage: processingStage,
                error: processingError,
                language: selectedLanguage
            )
        }
    }
    
    private var reprocessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reprocess")
                .font(.headline)
            
            OutputTypePicker(selection: $selectedOutputType, label: "Note style")
            
            if note.noteStatus == .ready || note.noteStatus == .failed {
                LanguagePicker(selection: $selectedLanguage)
            }
            
            HStack(spacing: 12) {
                Button {
                    transcribeAgain()
                } label: {
                    Label("Transcribe again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isProcessing || !audioAvailable)
                
                Button {
                    resummarizeOnly()
                } label: {
                    Label("Re-summarize", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
                .disabled(isProcessing || note.displayTranscript.isEmpty)
            }
            
            if !audioAvailable {
                Label("Audio deleted — re-summarize only", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .cardStyle()
    }
    
    private var metadataHeader: some View {
        HStack(spacing: 12) {
            Text(note.appLanguage.flag)
            Text(DurationFormatter.format(note.durationSeconds))
            if let provider = note.primaryProvider {
                Text(provider)
            }
            Spacer()
            statusLabel
        }
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        switch note.noteStatus {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle")
                .foregroundStyle(AppTheme.primary)
        case .processing:
            Label("Processing", systemImage: "hourglass")
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle")
                .foregroundStyle(AppTheme.error)
        case .draft:
            EmptyView()
        }
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            Text("Transcript").tag(0)
            Text("Summary").tag(1)
            Text("Actions").tag(2)
        }
        .pickerStyle(.segmented)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: transcriptTab
        case 1: summaryTab
        default: actionsTab
        }
    }
    
    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if note.segments.isEmpty {
                Text(note.displayTranscript.isEmpty ? "No transcript yet." : note.displayTranscript)
                    .font(.body)
            } else {
                ForEach(note.segments.sorted(by: { $0.segmentIndex < $1.segmentIndex }), id: \.id) { segment in
                    SegmentRow(
                        segment: segment,
                        isPlaying: playback.currentSegmentId == segment.id,
                        onPlay: { playSegment(segment) },
                        onEdit: {
                            editText = segment.text
                            editingSegment = segment
                        }
                    )
                }
            }
        }
        .cardStyle()
    }
    
    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let short = note.summaryShort, !short.isEmpty, !TranscriptTextFormatter.isRawJSON(short) {
                Text("Summary")
                    .font(.headline)
                Text(note.displaySummaryShort)
                    .font(.body)
            } else if !note.displaySummaryShort.isEmpty {
                Text("Summary")
                    .font(.headline)
                Text(note.displaySummaryShort)
                    .font(.body)
            }
            
            if let detailed = note.summaryDetailed, !detailed.isEmpty, detailed != note.summaryShort {
                Text("Detailed")
                    .font(.headline)
                Text(detailed)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            if let output = note.structuredOutput {
                if !output.keyIdeas.isEmpty {
                    sectionList(title: "Key Ideas", items: output.keyIdeas)
                }
                if !output.decisions.isEmpty {
                    sectionList(title: "Decisions", items: output.decisions)
                }
                if !output.openQuestions.isEmpty {
                    sectionList(title: "Open Questions", items: output.openQuestions)
                }
            }
        }
        .cardStyle()
    }
    
    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let output = note.structuredOutput, !output.actionItems.isEmpty {
                ForEach(output.actionItems) { item in
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(AppTheme.primary)
                        VStack(alignment: .leading) {
                            Text(item.text)
                            if let assignee = item.assignee {
                                Text("Assignee: \(assignee)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            } else {
                Text("No action items extracted.")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            if let draft = note.structuredOutput?.followUpEmailDraft, !draft.isEmpty {
                Divider()
                Text("Follow-up Email Draft")
                    .font(.headline)
                Text(draft)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .cardStyle()
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Export") { exportNote() }
                    .buttonStyle(PrimaryButtonStyle())
                
                EmailButton(note: note)
            }
            
            if let exportURL = try? environment.exportService.exportPlainText(note: note) {
                ShareLink(item: exportURL) {
                    Label("Share Text", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func sectionList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
            }
        }
    }
    
    private func playSegment(_ segment: TranscriptSegmentModel) {
        let url = environment.storageService.audioURL(for: note.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        playback.play(url: url, segment: segment)
    }
    
    private func toggleFavorite() {
        note.isFavorite.toggle()
        try? modelContext.save()
    }
    
    private func exportNote() {
        Task {
            _ = try? environment.exportService.exportPDF(note: note)
            _ = try? environment.exportService.exportMarkdown(note: note)
        }
    }
    
    private func applySelectionsToNote() {
        note.outputType = selectedOutputType.rawValue
        note.language = selectedLanguage.rawValue
    }
    
    private func transcribeAgain() {
        applySelectionsToNote()
        isProcessing = true
        processingError = nil
        processingStage = .transcribing
        
        Task {
            do {
                try await environment.processRecordingUseCase.transcribeAgain(note: note) { stage in
                    processingStage = stage
                }
                try? modelContext.save()
                selectedOutputType = note.noteOutputType
                try? await Task.sleep(nanoseconds: 600_000_000)
                isProcessing = false
            } catch {
                processingError = error.localizedDescription
                note.status = NoteStatus.failed.rawValue
                note.errorMessage = error.localizedDescription
                try? modelContext.save()
            }
        }
    }
    
    private func resummarizeOnly() {
        applySelectionsToNote()
        isProcessing = true
        processingError = nil
        processingStage = .summarizing
        
        Task {
            do {
                try await environment.processRecordingUseCase.resummarize(note: note) { stage in
                    processingStage = stage
                }
                try? modelContext.save()
                try? await Task.sleep(nanoseconds: 600_000_000)
                isProcessing = false
            } catch {
                processingError = error.localizedDescription
                note.status = NoteStatus.failed.rawValue
                note.errorMessage = error.localizedDescription
                try? modelContext.save()
            }
        }
    }
    
    private func segmentEditSheet(_ segment: TranscriptSegmentModel) -> some View {
        NavigationStack {
            VStack {
                TextEditor(text: $editText)
                    .padding()
                Spacer()
            }
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingSegment = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        segment.originalText = segment.text
                        segment.text = editText
                        segment.isUserCorrected = true
                        note.correctedTranscript = note.segments
                            .sorted(by: { $0.segmentIndex < $1.segmentIndex })
                            .map(\.text)
                            .joined(separator: " ")
                        note.updatedAt = .now
                        try? modelContext.save()
                        editingSegment = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegmentModel
    let isPlaying: Bool
    let onPlay: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle")
                    .foregroundStyle(AppTheme.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let speaker = SpeakerLabelFormatter.displayName(for: segment.speakerLabel) {
                        Text(speaker)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.speakerColor(for: segment.speakerLabel))
                    }
                    Text(timeLabel)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Text(segment.text)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(segment.isUnclear ? AppTheme.unclearHighlight : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if segment.isUnclear {
                    Label("Unclear (\(Int(segment.confidence * 100))% confidence)", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warning)
                }
            }
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
    
    private var timeLabel: String {
        DurationFormatter.format(segment.startTime)
    }
}

extension TranscriptSegmentModel: Identifiable {}
