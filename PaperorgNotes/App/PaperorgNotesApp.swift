import SwiftUI
import SwiftData

@main
struct PaperorgNotesApp: App {
    @State private var environment = AppEnvironment.live
    private let modelContainerResult: Result<ModelContainer, Error>

    init() {
        modelContainerResult = Self.makeModelContainer()
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

    private static func makeModelContainer() -> Result<ModelContainer, Error> {
        let schema = Schema([
            Note.self,
            TranscriptSegmentModel.self,
            StructuredSectionModel.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            return .success(try ModelContainer(for: schema, configurations: [config]))
        } catch {
            return .failure(error)
        }
    }
}
