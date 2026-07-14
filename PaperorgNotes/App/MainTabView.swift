import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var isUnlocked = false
    
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
        .preferredColorScheme(nil)
        .task {
            await environment.subscriptionService.refreshEntitlements()
        }
        .onAppear(perform: recoverInterruptedProcessing)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if settings.faceIDEnabled,
               oldPhase == .active,
               newPhase != .active,
               environment.recordingService.state == .idle {
                isUnlocked = false
            }
            if newPhase == .active, settings.hasCompletedPlanSelection {
                recoverInterruptedProcessing()
                Task { await environment.subscriptionService.refreshEntitlements() }
            }
        }
        .onChange(of: settings.faceIDEnabled) { _, enabled in
            if enabled {
                isUnlocked = false
            }
        }
    }

    private func recoverInterruptedProcessing() {
        let recoveredRecordings = environment.recordingService.recoverInterruptedRecordings()
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
            if needsRecovery, let recovered = environment.recordingService.recoverRecording(for: note.id) {
                applyRecovery(recovered, to: note)
            }
        }

        for note in notes where note.noteStatus == .processing {
            note.status = NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = "Processing was interrupted. You can transcribe again or re-summarize."
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
        note.status = NoteStatus.draft.rawValue
        note.processingStage = nil
        note.errorMessage = "Recording recovered after an interruption. Tap Transcribe again to process."
        note.updatedAt = .now
    }

    private func audioExists(for noteId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: environment.storageService.audioURL(for: noteId).path)
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        @Bindable var deepLink = environment.deepLinkHandler
        
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
        .onAppear {
            // Defer consuming the request until the record tab exists so a
            // cold-launch deep link cannot be lost behind privacy or Face ID.
            environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
        }
    }
}
