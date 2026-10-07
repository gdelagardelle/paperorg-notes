import AppKit
import SwiftData
import SwiftUI

@main
struct PaperorgNotesMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.live
    private let modelContainerResult: Result<ModelContainer, Error>

    init() {
        modelContainerResult = AppModelContainer.make()
    }

    var body: some Scene {
        MenuBarExtra("Paperorg Notes", systemImage: "mic.fill") {
            MacMenuBarPopover()
                .environment(environment)
                .background(MacLaunchHelper())
                .modifier(AttachedModelContainer(result: modelContainerResult))
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Paperorg Notes", id: "main") {
            switch modelContainerResult {
            case .success(let container):
                RootView()
                    .environment(environment)
                    .modelContainer(container)
                    .frame(minWidth: 960, minHeight: 640)
            case .failure(let error):
                StoreRecoveryView(error: error)
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Record") {
                    environment.deepLinkHandler.selectedTab = 0
                    MacWindowPresenter.showMainWindow()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
