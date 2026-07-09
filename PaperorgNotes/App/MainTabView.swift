import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
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
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
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
    }
}
