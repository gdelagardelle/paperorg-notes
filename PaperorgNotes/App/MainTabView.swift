import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var isUnlocked = false
    @State private var retryingNoteIDs: Set<UUID> = []
    
    var body: some View {
        @Bindable var settings = environment.settingsService
        
        Group {
            if !settings.hasAcceptedPrivacyPolicy {
                PrivacyConsentView()
            } else if !settings.hasCompletedPlanSelection {
                PlanSelectionView()
            } else if settings.faceIDEnabled && !isUnlocked && environment.recordingService.state == .idle {
                FaceIDLockView(isUnlocked: $isUnlocked)
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(.light)
        .task {
            // A background refresh should never surface as a paywall failure.
            // Explicit restore and purchase actions still report their errors.
            await environment.subscriptionService.refreshEntitlements(reportError: false)
            await retryWaitingTranscriptions()
        }
        .onAppear {
            recoverInterruptedProcessing()
            Task { await retryWaitingTranscriptions() }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if settings.faceIDEnabled,
               oldPhase == .active,
               newPhase != .active,
               environment.recordingService.state == .idle {
                isUnlocked = false
            }
            if newPhase == .active, settings.hasCompletedPlanSelection {
                recoverInterruptedProcessing()
                Task {
                    await environment.subscriptionService.refreshEntitlements(reportError: false)
                    await retryWaitingTranscriptions()
                }
            }
        }
        .onChange(of: environment.connectivityMonitor.isConnected) { _, isConnected in
            if isConnected {
                Task { await retryWaitingTranscriptions() }
            }
        }
        .onChange(of: settings.faceIDEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
            }
        }
        .onOpenURL { environment.deepLinkHandler.handle($0) }
    }

    private func recoverInterruptedProcessing() {
        // Never finalize checkpoints while a live recording session is open.
        // Widget launches fire scenePhase .active right after auto-start, which used to
        // move the in-progress temp file and stop the recorder after ~1 second.
        guard environment.recordingService.state == .idle else { return }

        let recoveredRecordings = environment.recordingService.recoverInterruptedRecordings(
            excludingSessionId: environment.recordingService.sessionId
        )
        let recoveredByNoteID = Dictionary(
            uniqueKeysWithValues: recoveredRecordings.map { ($0.noteId, $0) }
        )

        for note in notes {
            if let recovered = recoveredByNoteID[note.id] {
                applyRecovery(recovered, to: note)
                continue
            }

            let needsRecovery = note.noteStatus == .draft
                && (note.durationSeconds <= 0 || !audioExists(for: note.id))
            if needsRecovery,
               note.id != environment.recordingService.currentNoteId,
               let recovered = environment.recordingService.recoverRecording(for: note.id) {
                applyRecovery(recovered, to: note)
            }
        }

        for note in notes where note.noteStatus == .processing {
            let hasAudio = audioExists(for: note.id)
            note.status = hasAudio
                ? NoteStatus.waitingForNetwork.rawValue
                : NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = hasAudio
                ? nil
                : "Processing was interrupted and the recording file is unavailable."
            note.updatedAt = .now
        }

        environment.storageService.purgeExpiredAudio(
            notes: notes,
            retentionDays: environment.settingsService.effectiveAudioRetentionDays
        )

        do {
            try modelContext.save()
        } catch {
            print("Failed to recover interrupted notes: \(error.localizedDescription)")
        }
    }

    private func applyRecovery(_ recovered: RecoveredRecording, to note: Note) {
        note.audioFileName = recovered.audioURL.lastPathComponent
        note.durationSeconds = recovered.duration
        note.status = NoteStatus.waitingForNetwork.rawValue
        note.processingStage = nil
        note.errorMessage = nil
        note.updatedAt = .now
    }

    private func retryWaitingTranscriptions() async {
        guard environment.connectivityMonitor.isConnected,
              environment.recordingService.state == .idle else { return }

        for note in notes {
            let hasAudio = audioExists(for: note.id)
            guard OfflineTranscriptionRecoveryPolicy.shouldRetry(
                status: note.noteStatus,
                isConnected: environment.connectivityMonitor.isConnected,
                hasAudio: hasAudio,
                isInFlight: retryingNoteIDs.contains(note.id)
            ) else { continue }

            retryingNoteIDs.insert(note.id)
            do {
                try await environment.processRecordingUseCase.transcribeAgain(note: note) { _ in }
            } catch {
                // The use case persists either waiting-for-network or a terminal failure.
            }
            retryingNoteIDs.remove(note.id)
        }
    }

    private func audioExists(for noteId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: environment.storageService.audioURL(for: noteId).path)
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        @Bindable var deepLink = environment.deepLinkHandler
        let recording = environment.recordingService
        
        TabView(selection: $deepLink.selectedTab) {
            RecordView()
                .tabItem {
                    Label(L10n.Tab.record, systemImage: "mic.fill")
                }
                .tag(0)
            
            NotesListView()
                .tabItem {
                    Label(L10n.Tab.notes, systemImage: "doc.text.fill")
                }
                .tag(1)
            
            SearchView()
                .tabItem {
                    Label(L10n.Tab.search, systemImage: "magnifyingglass")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label(L10n.Tab.settings, systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(AppTheme.accent)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                AppBuildBadge()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if recording.state != .idle {
                RecordingInProgressBanner(
                    state: recording.state,
                    duration: recording.duration,
                    onOpenRecordTab: { deepLink.selectedTab = 0 }
                )
            }
        }
        .onAppear {
            // Defer consuming the request until the record tab exists so a
            // cold-launch deep link cannot be lost behind privacy or Face ID.
            environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
        }
    }
}
