import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MacWindowPresenter.showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MacWindowPresenter.showMainWindow()
        }
        return true
    }
}

enum MacWindowPresenter {
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .paperorgOpenMainWindow, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let window = NSApp.windows.first { window in
                window.canBecomeMain && !window.className.contains("StatusBar")
            }
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let paperorgOpenMainWindow = Notification.Name("paperorgOpenMainWindow")
}
