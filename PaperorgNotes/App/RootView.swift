import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    #if os(iOS)
    @State private var isUnlocked = false
    #endif
    @State private var retryingNoteIDs: Set<UUID> = []

    var body: some View {
        @Bindable var settings = environment.settingsService

        Group {
            if !settings.hasAcceptedPrivacyPolicy {
                PrivacyConsentView()
            } else if !settings.hasCompletedPlanSelection {
                PlanSelectionView()
            } else {
                authenticatedShell(settings: settings)
            }
        }
        .task {
            await bootstrapIncludedMinutesIfNeeded()
            await environment.subscriptionService.refreshEntitlements(reportError: false)
            await retryWaitingTranscriptions()
        }
        .onAppear {
            recoverInterruptedProcessing()
            Task { await retryWaitingTranscriptions() }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            #if os(iOS)
            if settings.faceIDEnabled,
               oldPhase == .active,
               newPhase != .active,
               environment.recordingService.state == .idle {
                isUnlocked = false
            }
            #endif
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
        #if os(iOS)
        .onChange(of: settings.faceIDEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
            }
        }
        #endif
        .onOpenURL { environment.deepLinkHandler.handle($0) }
    }

    @ViewBuilder
    private func authenticatedShell(settings: SettingsService) -> some View {
        #if os(iOS)
        if settings.faceIDEnabled,
           !isUnlocked,
           environment.recordingService.state == .idle {
            FaceIDLockView(isUnlocked: $isUnlocked)
        } else {
            mainShell
        }
        #else
        mainShell
        #endif
    }

    @ViewBuilder
    private var mainShell: some View {
        #if os(macOS)
        MacMainView()
        #else
        MainTabView()
        #endif
    }

    private func bootstrapIncludedMinutesIfNeeded() async {
        guard environment.settingsService.hasCompletedPlanSelection else { return }
        guard !environment.settingsService.usesBackendProcessing else { return }
        do {
            _ = try await environment.proBackendClient.register()
        } catch {
            // Record and Settings will offer the included-minutes sheet instead.
        }
    }

    private func recoverInterruptedProcessing() {
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
