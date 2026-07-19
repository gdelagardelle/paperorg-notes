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
    @State private var showQuickRecordQueued = false
    @State private var autoEmailError: String?
    @State private var showPaywall = false
    
    private var isRecordingSession: Bool {
        environment.recordingService.state == .recording || environment.recordingService.state == .paused
    }

    private var recordLanguageOptions: [AppLanguage] {
        environment.settingsService.autoDetectLanguage
            ? AppLanguage.recordPickerLanguages
            : AppLanguage.spokenLanguages
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    AppBrandHeader()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    setupCard
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    recordHeroCard
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if let warning = environment.recordingService.qualityWarning {
                    Section {
                        qualityWarningBanner(warning)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                recentSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppScreenBackground())
            .navigationBarHidden(true)
            .onAppear {
                if environment.settingsService.autoDetectLanguage {
                    selectedLanguage = .autoDetect
                } else {
                    selectedLanguage = environment.settingsService.defaultLanguage
                }
                selectedOutputType = environment.settingsService.defaultOutputType
                environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
                relinkActiveNoteIfRecording()
                handleQuickRecordRequestIfNeeded()
            }
            .onChange(of: environment.recordingService.state) { _, newState in
                pulseAnimation = newState == .recording
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
            .alert(L10n.Record.failedTitle, isPresented: Binding(
                get: { processingError != nil && !showProcessing },
                set: { if !$0 { processingError = nil } }
            )) {
                Button(L10n.Common.ok, role: .cancel) {}
            } message: {
                Text(processingError ?? "")
            }
            .alert(L10n.Record.quickRecordQueuedTitle, isPresented: $showQuickRecordQueued) {
                Button(L10n.Common.ok, role: .cancel) {}
            } message: {
                Text(L10n.Record.quickRecordQueuedMessage)
            }
            .alert("Email Not Sent", isPresented: Binding(
                get: { autoEmailError != nil },
                set: { if !$0 { autoEmailError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(autoEmailError ?? "")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
    
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Record.language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recordLanguageOptions) { language in
                            SelectionChip(
                                title: "\(language.flag) \(language.displayName)",
                                isSelected: selectedLanguage == language,
                                action: { selectedLanguage = language }
                            )
                            .disabled(isRecordingSession)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Record.noteStyle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(OutputType.allCases) { type in
                            SelectionChip(
                                title: type.displayName,
                                icon: type.icon,
                                isSelected: selectedOutputType == type,
                                action: { selectedOutputType = type }
                            )
                            .disabled(isRecordingSession)
                        }
                    }
                }
            }
        }
        .surfaceCard()
        .opacity(isRecordingSession ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.2), value: isRecordingSession)
    }
    
    private var recordHeroCard: some View {
        VStack(spacing: 20) {
            RecordHeroStack(
                state: environment.recordingService.state,
                pulseAnimation: pulseAnimation,
                audioLevel: environment.recordingService.audioLevel,
                action: toggleRecording
            )
            
            Text(DurationFormatter.format(environment.recordingService.duration))
                .font(.system(size: 36, weight: .light, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
            
            Text(recordStatusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            
            if isRecordingSession {
                HStack(spacing: 12) {
                    Button(action: togglePause) {
                        RecordControlButton(
                            title: environment.recordingService.state == .paused ? "Resume" : "Pause",
                            systemImage: environment.recordingService.state == .paused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(showProcessing)
                    
                    Button(action: stopRecording) {
                        RecordControlButton(
                            title: "Stop",
                            systemImage: "stop.fill",
                            role: .destructive
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(showProcessing)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 28)
    }
    
    private func qualityWarningBanner(_ warning: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(warning)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 14, cornerRadius: 14)
    }
    
    private var recentSection: some View {
        Section {
            if recentNotes.prefix(5).isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.accent.opacity(0.7))
                    Text(L10n.Record.emptyTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L10n.Record.emptySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .surfaceCard(padding: 28)
            } else {
                ForEach(Array(recentNotes.prefix(5))) { note in
                    NavigationLink {
                        NoteDetailView(note: note)
                    } label: {
                        NoteCardRow(note: note, style: .compact)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteRecentNote(note)
                        } label: {
                            Label(L10n.NoteDetail.delete, systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            AppSectionHeader(title: "Recent notes", subtitle: "Pick up where you left off")
                .textCase(nil)
                .padding(.top, 12)
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    private var recordStatusText: String {
        switch environment.recordingService.state {
        case .idle: return "Tap to start recording"
        case .recording: return "Listening… tap to finish"
        case .paused: return "Paused — tap to resume, or use Stop below"
        }
    }
    
    private func toggleRecording() {
        switch environment.recordingService.state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .paused:
            environment.recordingService.resume()
        }
    }
    
    private func startRecording() {
        if environment.settingsService.selectedPlan == .pro,
           !environment.subscriptionService.isProActive {
            showPaywall = true
            return
        }

        if !environment.settingsService.usesProBackend,
           environment.settingsService.openAIAPIKey?.isEmpty != false {
            processingError = "Add your OpenAI API key in Settings → Transcription, or upgrade to Paperorg Pro."
            return
        }

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
        guard environment.recordingService.state != .idle else { return }
        guard !showProcessing else { return }

        pulseAnimation = false
        showProcessing = true
        processingStage = .savingAudio
        processingError = nil
        
        Task {
            await BackgroundTaskRunner.run("StopRecording") {
                var finalizedNoteId: UUID?
                do {
                    let result = try await environment.recordingService.stop()
                    finalizedNoteId = result.noteId
                    let note = try noteForRecordingResult(result.noteId)
                    
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
                    if let noteId = finalizedNoteId ?? activeNote?.id,
                       let note = try? noteForRecordingResult(noteId) {
                        if note.durationSeconds <= 0,
                           FileManager.default.fileExists(
                            atPath: environment.storageService.audioURL(for: noteId).path
                           ) {
                            note.durationSeconds = AudioTrimService.playableDuration(
                                of: environment.storageService.audioURL(for: noteId)
                            )
                        }
                        note.status = NoteStatus.failed.rawValue
                        note.errorMessage = processingError
                        note.updatedAt = .now
                        try? modelContext.save()
                    }
                    showProcessing = false
                    startQueuedQuickRecordIfPossible()
                }
            }
        }
    }

    private func noteForRecordingResult(_ noteId: UUID) throws -> Note {
        if let activeNote, activeNote.id == noteId {
            return activeNote
        }
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteId })
        descriptor.fetchLimit = 1
        guard let note = try modelContext.fetch(descriptor).first else {
            throw RecordingError.saveFailed("Recording was saved, but its note could not be found.")
        }
        activeNote = note
        return note
    }

    private func safeProcessingError(_ error: Error) -> String {
        if let error = error as? RecordingError {
            return error.localizedDescription
        }
        if let error = error as? TranscriptionError {
            return error.localizedDescription
        }
        if error is DecodingError {
            return "Processing failed because the server returned an unexpected response. Try again, or reprocess from the note."
        }
        return error.localizedDescription
    }
    
    private func relinkActiveNoteIfRecording() {
        guard activeNote == nil, let noteId = environment.recordingService.currentNoteId else { return }
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteId })
        descriptor.fetchLimit = 1
        activeNote = try? modelContext.fetch(descriptor).first
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

        Task {
            do {
                let payload = try environment.emailService.buildPayload(
                    for: note,
                    exportService: environment.exportService
                )
                try await environment.emailDeliveryService.send(payload)
            } catch {
                autoEmailError = friendlyEmailErrorMessage(for: error)
            }
        }
    }

    private func friendlyEmailErrorMessage(for error: Error) -> String {
        if let backendError = error as? ProBackendError {
            return backendError.localizedDescription
        }
        if let deliveryError = error as? EmailDeliveryError {
            return deliveryError.localizedDescription
        }
        if let emailError = error as? EmailError {
            return emailError.localizedDescription
        }
        if error is DecodingError {
            return "Could not read the server response. Check your connection and try again."
        }
        return error.localizedDescription
    }

    private func deleteRecentNote(_ note: Note) {
        try? environment.deleteNoteUseCase.deleteNote(note, context: modelContext)
    }
}

struct ProcessingView: View {
    let stage: ProcessingStage
    let error: String?
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppTheme.border)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 24)
            
            if error != nil {
                errorContent
            } else {
                progressContent
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(AppScreenBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
    
    private var errorContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.error)
            
            AppSectionHeader(
                title: "Processing failed",
                subtitle: error ?? "Something went wrong while finishing your note."
            )
            
            Button("Done") { dismiss() }
                .buttonStyle(AccentButtonStyle())
        }
    }
    
    private var progressContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text("Finishing your note")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("This usually takes under a minute.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            VStack(spacing: 14) {
                ForEach(ProcessingStage.allCases.filter { $0 != .ready }, id: \.self) { step in
                    stageRow(step)
                }
            }
            .surfaceCard()
            
            if stage == .transcribing && language == .luxembourgish {
                Label("Using LuxASR for Lëtzebuergesch", systemImage: "globe.europe.africa.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            if let detail = stage.detailMessage(for: language) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func stageRow(_ step: ProcessingStage) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(stepBackground(for: step))
                    .frame(width: 32, height: 32)
                stepIcon(for: step)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(step.displayName)
                    .font(.subheadline.weight(step == stage ? .semibold : .regular))
                    .foregroundStyle(step == stage ? AppTheme.textPrimary : AppTheme.textSecondary)
                if step == stage, let detail = step.detailMessage(for: language) {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func stepIcon(for step: ProcessingStage) -> some View {
        if stageOrder(step) < stageOrder(stage) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
        } else if step == stage {
            ProgressView()
                .tint(AppTheme.accent)
                .scaleEffect(0.7)
        } else {
            Circle()
                .fill(AppTheme.border)
                .frame(width: 8, height: 8)
        }
    }
    
    private func stepBackground(for step: ProcessingStage) -> Color {
        if stageOrder(step) < stageOrder(stage) {
            return AppTheme.primary
        }
        if step == stage {
            return AppTheme.accentSoft
        }
        return AppTheme.background
    }
    
    private func stageOrder(_ step: ProcessingStage) -> Int {
        ProcessingStage.allCases.firstIndex(of: step) ?? 0
    }
}
