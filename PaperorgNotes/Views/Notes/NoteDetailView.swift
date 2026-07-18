import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note
    
    @State private var selectedTab = 0
    @State private var selectedOutputType: OutputType = .meetingNotes
    @State private var selectedLanguage: AppLanguage = .luxembourgish
    @State private var isProcessing = false
    @State private var processingStage: ProcessingStage = .transcribing
    @State private var processingError: String?
    @State private var editingSegment: TranscriptSegmentModel?
    @State private var editText = ""
    @State private var showDeleteAudioConfirm = false
    @State private var showDeleteNoteConfirm = false
    @State private var exportURLs: [URL] = []
    @State private var showExportShare = false
    @State private var exportError: String?
    @State private var showAudioTrim = false
    @State private var trimError: String?
    @StateObject private var playback = AudioPlaybackService()
    
    private var audioAvailable: Bool {
        FileManager.default.fileExists(atPath: environment.storageService.audioURL(for: note.id).path)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataHeader
                if audioAvailable {
                    NoteAudioPlayerSection(
                        note: note,
                        audioURL: environment.storageService.audioURL(for: note.id),
                        playback: playback,
                        onTrim: { showAudioTrim = true }
                    )
                } else if note.audioDeletedAt != nil {
                    SettingsSectionHint(text: "Audio was removed after processing. Re-summarize or transcribe again if you kept the transcript.")
                } else if note.noteStatus == .draft {
                    SettingsSectionHint(text: "No recording file found. If this note stays empty after reopening the app, the audio was likely lost when recording stopped.")
                }
                if note.noteStatus == .failed, let error = note.errorMessage, !error.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.error)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .surfaceCard(padding: 14, cornerRadius: 14)
                }
                NoteOrganizerSection(note: note)
                reprocessSection
                tabPicker
                tabContent
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(AppScreenBackground())
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedOutputType = note.noteOutputType
            selectedLanguage = note.appLanguage
            attemptRecordingRecovery()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: toggleFavorite) {
                        Image(systemName: note.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(note.isFavorite ? AppTheme.accent : AppTheme.textSecondary)
                    }
                    
                    Menu {
                        if audioAvailable {
                            Button(role: .destructive) {
                                showDeleteAudioConfirm = true
                            } label: {
                                Label(L10n.NoteDetail.deleteRecording, systemImage: "waveform.slash")
                            }
                        }
                        
                        Button(role: .destructive) {
                            showDeleteNoteConfirm = true
                        } label: {
                            Label(L10n.NoteDetail.deleteNote, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .alert(L10n.NoteDetail.deleteRecordingTitle, isPresented: $showDeleteAudioConfirm) {
            Button(L10n.NoteDetail.deleteAudio, role: .destructive) {
                try? environment.deleteNoteUseCase.deleteAudio(for: note, context: modelContext)
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.NoteDetail.deleteRecordingMessage)
        }
        .alert(L10n.NoteDetail.deleteNoteTitle, isPresented: $showDeleteNoteConfirm) {
            Button(L10n.NoteDetail.delete, role: .destructive) {
                try? environment.deleteNoteUseCase.deleteNote(note, context: modelContext)
                dismiss()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.NoteDetail.deleteNoteMessage)
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
        .sheet(isPresented: $showExportShare) {
            ActivityShareSheet(items: exportURLs)
        }
        .alert(L10n.NoteDetail.exportFailed, isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Trim Failed", isPresented: Binding(
            get: { trimError != nil },
            set: { if !$0 { trimError = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(trimError ?? "")
        }
        .sheet(isPresented: $showAudioTrim) {
            AudioTrimSheet(audioURL: environment.storageService.audioURL(for: note.id)) { start, end in
                Task { await applyTrim(start: start, end: end) }
            }
        }
    }
    
    private var reprocessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: L10n.NoteDetail.reprocessTitle, subtitle: L10n.NoteDetail.reprocessSubtitle)

            OutputTypePicker(selection: $selectedOutputType, label: L10n.NoteDetail.noteStyle)

            if note.noteStatus == .ready || note.noteStatus == .failed {
                LanguagePicker(selection: $selectedLanguage)
            }

            HStack(spacing: 12) {
                Button {
                    transcribeAgain()
                } label: {
                    Label(L10n.NoteDetail.transcribeAgain, systemImage: "arrow.clockwise")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(isProcessing || !audioAvailable)

                Button {
                    resummarizeOnly()
                } label: {
                    Label(L10n.NoteDetail.resummarize, systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isProcessing || note.displayTranscript.isEmpty)
            }

            if !audioAvailable {
                SettingsSectionHint(text: L10n.NoteDetail.audioDeletedHint)
            }
        }
        .surfaceCard()
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                NoteStatusBadge(status: note.noteStatus)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MetaPill(text: note.appLanguage.displayName, icon: "globe")
                    MetaPill(text: DurationFormatter.format(note.durationSeconds), icon: "clock")
                    MetaPill(text: note.noteOutputType.displayName, icon: note.noteOutputType.icon)
                    if let provider = note.primaryProvider, !provider.isEmpty {
                        MetaPill(text: provider, icon: "waveform")
                    }
                }
            }
        }
        .surfaceCard()
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: note.createdAt)
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            Text(L10n.NoteDetail.tabTranscript).tag(0)
            Text(L10n.NoteDetail.tabSummary).tag(1)
            Text(L10n.NoteDetail.tabActions).tag(2)
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
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
                Text(note.displayTranscript.isEmpty ? L10n.NoteDetail.noTranscript : note.displayTranscript)
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
        .surfaceCard()
    }
    
    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let short = note.summaryShort, !short.isEmpty, !TranscriptTextFormatter.isRawJSON(short) {
                Text(L10n.NoteDetail.summaryHeader)
                    .font(.headline)
                Text(note.displaySummaryShort)
                    .font(.body)
            } else if !note.displaySummaryShort.isEmpty {
                Text(L10n.NoteDetail.summaryHeader)
                    .font(.headline)
                Text(note.displaySummaryShort)
                    .font(.body)
            }
            
            if let detailed = note.summaryDetailed, !detailed.isEmpty, detailed != note.summaryShort {
                Text(L10n.NoteDetail.detailed)
                    .font(.headline)
                Text(detailed)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            if let output = note.structuredOutput {
                if !output.keyIdeas.isEmpty {
                    sectionList(title: L10n.NoteDetail.keyIdeas, items: output.keyIdeas)
                }
                if !output.decisions.isEmpty {
                    sectionList(title: L10n.NoteDetail.decisions, items: output.decisions)
                }
                if !output.openQuestions.isEmpty {
                    sectionList(title: L10n.NoteDetail.openQuestions, items: output.openQuestions)
                }
            }
        }
        .surfaceCard()
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
                                Text(L10n.NoteDetail.assignee(assignee))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            } else {
                Text(L10n.NoteDetail.noActionItems)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            if let draft = note.structuredOutput?.followUpEmailDraft, !draft.isEmpty {
                Divider()
                Text(L10n.NoteDetail.followUpEmail)
                    .font(.headline)
                Text(draft)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .surfaceCard()
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(L10n.NoteDetail.export) { exportNote() }
                    .buttonStyle(AccentButtonStyle())

                EmailButton(note: note)
            }

            Button(L10n.NoteDetail.shareText) {
                sharePlainText()
            }
            .buttonStyle(SecondaryButtonStyle())

            if let debug = note.processingDebug, !debug.isEmpty {
                ShareLink(item: debug) {
                    Label(L10n.NoteDetail.shareDebug, systemImage: "ladybug")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
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
    
    private func applyTrim(start: TimeInterval, end: TimeInterval) async {
        let source = environment.storageService.audioURL(for: note.id)
        do {
            let trimmed = try await AudioTrimService.trim(sourceURL: source, start: start, end: end)
            try environment.storageService.replaceAudio(at: source, with: trimmed)
            note.durationSeconds = end - start
            note.audioDeletedAt = nil
            note.updatedAt = .now
            playback.stopFullPlayback()
            playback.prepareFullPlayback(url: source)
            try? modelContext.save()
        } catch {
            trimError = error.localizedDescription
        }
    }

    private func toggleFavorite() {
        note.isFavorite.toggle()
        try? modelContext.save()
    }
    private func exportNote() {
        do {
            exportURLs = [
                try environment.exportService.exportPlainText(note: note),
                try environment.exportService.exportMarkdown(note: note),
                try environment.exportService.exportPDF(
                    note: note,
                    branding: ExportBranding.from(
                        settings: environment.settingsService,
                        storage: environment.storageService
                    )
                )
            ]
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func sharePlainText() {
        do {
            exportURLs = [try environment.exportService.exportPlainText(note: note)]
            showExportShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }
    
    private func applySelectionsToNote() {
        note.outputType = selectedOutputType.rawValue
        note.language = selectedLanguage.rawValue
    }

    private func attemptRecordingRecovery() {
        guard !audioAvailable else { return }
        guard note.noteStatus == .draft || note.durationSeconds <= 0 else { return }
        guard let recovered = environment.recordingService.recoverRecording(for: note.id) else { return }

        note.audioFileName = recovered.audioURL.lastPathComponent
        note.durationSeconds = recovered.duration
        note.status = NoteStatus.draft.rawValue
        note.processingStage = nil
        note.errorMessage = "Recording recovered. Tap Transcribe again to process."
        note.updatedAt = .now
        try? modelContext.save()
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
                isProcessing = false
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
                isProcessing = false
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
            .navigationTitle(L10n.NoteDetail.editSegment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { editingSegment = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.NoteDetail.save) {
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
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(isPlaying ? AppTheme.accent : AppTheme.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

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
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(segment.isUnclear ? AppTheme.unclearHighlight : AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if segment.isUnclear {
                    Label(L10n.NoteDetail.segmentUnclear(confidence: Int(segment.confidence * 100)), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent)
                }
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.primarySoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private var timeLabel: String {
        DurationFormatter.format(segment.startTime)
    }
}

extension TranscriptSegmentModel: Identifiable {}
