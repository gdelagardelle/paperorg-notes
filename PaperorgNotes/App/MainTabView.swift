import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var isUnlocked = true
    
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
    }

    private func recoverInterruptedProcessing() {
        for note in notes where note.noteStatus == .processing {
            note.status = NoteStatus.failed.rawValue
            note.processingStage = nil
            note.errorMessage = "Processing was interrupted. You can transcribe again or re-summarize."
            note.updatedAt = .now
        }
        try? modelContext.save()
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
            environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
        }
    }
}
