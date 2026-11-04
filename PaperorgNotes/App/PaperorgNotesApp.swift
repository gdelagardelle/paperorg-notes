import SwiftUI
import SwiftData

@main
struct PaperorgNotesApp: App {
    @State private var environment = AppEnvironment.live
    private let modelContainerResult: Result<ModelContainer, Error>

    init() {
        ContinuedTranscription.register()
        modelContainerResult = AppModelContainer.make()
        if case .success(let container) = modelContainerResult {
            WatchRecordingInbox.shared.start(environment: .live, container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch modelContainerResult {
            case .success(let container):
                RootView()
                    .environment(environment)
                    .modelContainer(container)
                    .onOpenURL { environment.deepLinkHandler.handle($0) }
            case .failure(let error):
                StoreRecoveryView(error: error)
            }
        }
    }
}
