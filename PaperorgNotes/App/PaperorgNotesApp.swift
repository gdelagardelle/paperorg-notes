import SwiftUI
import SwiftData

@main
struct PaperorgNotesApp: App {
    @State private var environment = AppEnvironment.live
    
    var sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(sharedModelContainer)
                .onOpenURL { environment.deepLinkHandler.handle($0) }
        }
    }
}
