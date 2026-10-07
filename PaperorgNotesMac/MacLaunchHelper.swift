import SwiftUI

/// Opens the main library window at launch while keeping the menu-bar extra.
struct MacLaunchHelper: View {
    @Environment(\.openWindow) private var openWindow
    private static var didOpenAtLaunch = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                guard !Self.didOpenAtLaunch else { return }
                Self.didOpenAtLaunch = true
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .paperorgOpenMainWindow)) { _ in
                openWindow(id: "main")
            }
    }
}
