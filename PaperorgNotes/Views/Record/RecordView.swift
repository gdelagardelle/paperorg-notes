import SwiftUI
import SwiftData

struct RecordView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var recentNotes: [Note]
    
    @State private var selectedLanguage: AppLanguage = .luxembourgish
    @State private var selectedOutputType: OutputType = .meetingNotes
    @State private var activeNote: Note?
    @State private var showProcessing = false
    @State private var processingStage: ProcessingStage = .savingAudio
    @State private var processingError: String?
    @State private var pulseAnimation = false
    @State private var pendingEmailPayload: EmailPayload?
    @State private var postRecordingEmailPresentation: EmailPresentation?
    @State private var showQuickRecordQueued = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    languagePicker
                    recordButton
                    outputTypePicker
                    
                    if let warning = environment.recordingService.qualityWarning {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    recentSection
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Paperorg Notes")
            .onAppear {
                selectedLanguage = environment.settingsService.defaultLanguage
                selectedOutputType = environment.settingsService.defaultOutputType
                environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
                handleQuickRecordRequestIfNeeded()
            }
            .onChange(of: environment.deepLinkHandler.pendingQuickRecord) { _, pending in
                if pending {
                    handleQuickRecordRequestIfNeeded()
                }
            }
            .sheet(isPresented: $showProcessing) {
                ProcessingView(
                    stage: processingStage,
                    error: processingError,
                    language: selectedLanguage
                )
            }
            .sheet(item: $postRecordingEmailPresentation) { presentation in
                switch presentation {
                case .review(let payload, _):
                    if let note = activeNote {
                        ReviewBeforeSendView(note: note, payload: payload) { reviewed in
                            postRecordingEmailPresentation = .compose(reviewed, UUID())
                        }
                    }
                case .compose(let payload, _):
                    EmailComposeSheet(payload: payload)
                }
            }
            .alert("Recording Failed", isPresented: Binding(
                get: { processingError != nil && !showProcessing },
                set: { if !$0 { processingError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(processingError ?? "")
            }
            .alert("Quick Record Queued", isPresented: $showQuickRecordQueued) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your recording will start after the current recording finishes processing.")
            }
        }
    }
    
    private var languagePicker: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button("\(lang.flag) \(lang.displayName)") {
                    selectedLanguage = lang
                }
            }
        } label: {
            HStack {
                Text(selectedLanguage.flag)
                Text(selectedLanguage.displayName)
                    .font(.subheadline.bold())
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.surface)
            .clipShape(Capsule())
        }
    }
    
    private var recordButton: some View {
        VStack(spacing: 12) {
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(recordButtonColor.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.08 : 1.0)
                        .animation(
                            environment.recordingService.state == .recording
                                ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                                : .default,
                            value: pulseAnimation
                        )
                    
                    Circle()
                        .fill(recordButtonColor)
                        .frame(width: 88, height: 88)
                    
                    Image(systemName: recordIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
            }
            .onAppear { pulseAnimation = environment.recordingService.state == .recording }
            
            Text(DurationFormatter.format(environment.recordingService.duration))
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text(recordStatusText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            
            if environment.recordingService.state == .recording || environment.recordingService.state == .paused {
                HStack(spacing: 20) {
                    Button(action: togglePause) {
                        Label(
                            environment.recordingService.state == .paused ? "Resume" : "Pause",
                            systemImage: environment.recordingService.state == .paused ? "play.fill" : "pause.fill"
                        )
                    }
                    
                    Button(role: .destructive, action: stopRecording) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
                .font(.subheadline.bold())
            }
        }
    }
    
    private var outputTypePicker: some View {
        OutputTypePicker(selection: $selectedOutputType, label: "Note style")
    }
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.headline)
            
            if recentNotes.prefix(5).isEmpty {
                Text("No recordings yet")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(recentNotes.prefix(5)) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        RecentNoteRow(note: note)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var recordButtonColor: Color {
        switch environment.recordingService.state {
        case .recording, .paused, .idle: return AppTheme.accent
        }
    }
    
    private var recordIcon: String {
        switch environment.recordingService.state {
        case .idle: return "mic.fill"
        case .recording: return "waveform"
        case .paused: return "pause.fill"
        }
    }
    
    private var recordStatusText: String {
        switch environment.recordingService.state {
        case .idle: return "Tap to record"
        case .recording: return "Recording…"
        case .paused: return "Paused"
        }
    }
    
    private func toggleRecording() {
        switch environment.recordingService.state {
        case .idle:
            startRecording()
        case .recording, .paused:
            stopRecording()
        }
    }
    
    private func startRecording() {
        let noteId = UUID()
        
        Task {
            do {
                try await environment.recordingService.start(noteId: noteId)
                let note = Note(
                    id: noteId,
                    audioFileName: "\(noteId.uuidString).m4a",
                    language: selectedLanguage,
                    outputType: selectedOutputType,
                    status: .draft
                )
                modelContext.insert(note)
                activeNote = note
                do {
                    try modelContext.save()
                } catch {
                    environment.recordingService.cancel()
                    modelContext.delete(note)
                    throw RecordingError.saveFailed("Could not create the recording. Please try again.")
                }
                pulseAnimation = true
            } catch {
                processingError = error.localizedDescription
            }
        }
    }
    
    private func togglePause() {
        if environment.recordingService.state == .recording {
            environment.recordingService.pause()
        } else {
            environment.recordingService.resume()
        }
    }
    
    private func stopRecording() {
        pulseAnimation = false
        showProcessing = true
        processingStage = .savingAudio
        processingError = nil
        
        Task {
            do {
                let result = try await environment.recordingService.stop()
                guard let note = activeNote else {
                    throw RecordingError.saveFailed("Recording was saved, but its note could not be found.")
                }
                
                note.durationSeconds = result.duration
                note.status = NoteStatus.processing.rawValue
                try modelContext.save()
                
                try await environment.processRecordingUseCase.execute(
                    note: note,
                    audioURL: result.audioURL
                ) { stage in
                    processingStage = stage
                }
                
                try modelContext.save()
                
                preparePostRecordingEmail(for: note)
                
                try? await Task.sleep(nanoseconds: 800_000_000)
                showProcessing = false
                startQueuedQuickRecordIfPossible()
            } catch {
                processingError = safeProcessingError(error)
                activeNote?.status = NoteStatus.failed.rawValue
                activeNote?.errorMessage = processingError
                if let activeNote {
                    activeNote.updatedAt = .now
                    try? modelContext.save()
                }
                showProcessing = false
                startQueuedQuickRecordIfPossible()
            }
        }
    }

    private func safeProcessingError(_ error: Error) -> String {
        if let error = error as? RecordingError {
            return error.localizedDescription
        }
        return "Processing failed. Your recording remains available to retry."
    }
    
    private func handleQuickRecordRequestIfNeeded() {
        guard environment.deepLinkHandler.pendingQuickRecord else { return }
        guard environment.recordingService.state == .idle, !showProcessing else {
            showQuickRecordQueued = true
            return
        }
        
        let prefs = environment.deepLinkHandler.quickRecordPreferences()
        environment.deepLinkHandler.clearQuickRecordFlag()
        if let language = prefs.language {
            selectedLanguage = language
        }
        if let outputType = prefs.outputType {
            selectedOutputType = outputType
        }
        
        startRecording()
    }

    private func startQueuedQuickRecordIfPossible() {
        guard environment.deepLinkHandler.pendingQuickRecord else { return }
        handleQuickRecordRequestIfNeeded()
    }
    
    private func preparePostRecordingEmail(for note: Note) {
        guard note.noteStatus == .ready,
              environment.emailService.shouldSendAfterTranscription else { return }
        
        do {
            let payload = try environment.emailService.buildPayload(
                for: note,
                exportService: environment.exportService
            )
            pendingEmailPayload = payload
            presentPostRecordingEmail()
        } catch {
            // Silently skip auto-email if not configured
        }
    }

    private func presentPostRecordingEmail() {
        guard let payload = pendingEmailPayload else { return }
        postRecordingEmailPresentation = .compose(payload, UUID())
    }
}

struct RecentNoteRow: View {
    let note: Note
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(note.appLanguage.flag)
                    Text(DurationFormatter.format(note.durationSeconds))
                    Text(note.noteOutputType.displayName)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .font(.caption)
            }
            Spacer()
            statusBadge
        }
        .cardStyle()
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch note.noteStatus {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.primary)
        case .processing:
            ProgressView()
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.error)
        case .draft:
            Image(systemName: "circle")
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

struct ProcessingView: View {
    let stage: ProcessingStage
    let error: String?
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            if error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.error)
                Text("Processing Failed")
                    .font(.title2.bold())
                Text(error ?? "")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Processing your recording")
                    .font(.title2.bold())
                
                VStack(alignment: .leading, spacing: 16) {
                    stageRow(.savingAudio)
                    stageRow(.transcribing)
                    stageRow(.checkingQuality)
                    stageRow(.summarizing)
                    stageRow(.ready)
                }
                .cardStyle()
                
                if stage == .transcribing && language == .luxembourgish {
                    Text("Using LuxASR for Lëtzebuergesch")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                if let detail = stage.detailMessage(for: language) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if stage != .ready {
                    ProgressView()
                }
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
    
    private func stageRow(_ s: ProcessingStage) -> some View {
        HStack {
            if stageOrder(s) < stageOrder(stage) || stage == .ready && s == .ready {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.primary)
            } else if s == stage {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
            }
            Text(s.displayName)
                .font(.subheadline)
                .foregroundStyle(s == stage ? AppTheme.textPrimary : AppTheme.textSecondary)
        }
    }
    
    private func stageOrder(_ s: ProcessingStage) -> Int {
        ProcessingStage.allCases.firstIndex(of: s) ?? 0
    }
}
