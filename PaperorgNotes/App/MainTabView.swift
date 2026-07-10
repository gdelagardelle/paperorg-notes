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
            } else if settings.faceIDEnabled && !isUnlocked {
                FaceIDLockView(isUnlocked: $isUnlocked)
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(nil)
        .onAppear(perform: recoverInterruptedProcessing)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && settings.faceIDEnabled {
                isUnlocked = false
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
                note.audioFileName = recovered.audioURL.lastPathComponent
                note.durationSeconds = recovered.duration
                note.status = NoteStatus.draft.rawValue
                note.processingStage = nil
                note.errorMessage = "Recording recovered after an interruption. You can transcribe it when ready."
                note.updatedAt = .now
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
            retentionDays: environment.settingsService.deleteAudioAfterDays
        )

        do {
            try modelContext.save()
        } catch {
            print("Failed to recover interrupted notes: \(error.localizedDescription)")
        }
    }
}

struct MainTabView: View {
    @Environment(AppEnvironment.self) private var environment
    
    var body: some View {
        @Bindable var deepLink = environment.deepLinkHandler
        
        TabView(selection: $deepLink.selectedTab) {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
                .tag(0)
            
            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "doc.text.fill")
                }
                .tag(1)
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(AppTheme.primary)
        .onAppear {
            // Defer consuming the request until the record tab exists so a
            // cold-launch deep link cannot be lost behind privacy or Face ID.
            environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
        }
    }
}
