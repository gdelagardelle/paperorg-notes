import SwiftUI

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
            environment.deepLinkHandler.consumeAppGroupQuickRecordFlag()
            if ProcessInfo.processInfo.arguments.contains("-showPaywall") {
                environment.deepLinkHandler.pendingPaywall = true
                environment.deepLinkHandler.selectedTab = 3
            }
        }
    }
}
