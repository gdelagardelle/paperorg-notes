import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ActivityShareSheet: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        ActivityShareSheetRepresentable(items: items, dismiss: dismiss)
        #else
        MacShareSheet(items: items, dismiss: dismiss)
        #endif
    }
}

#if os(iOS)
enum SharePresenter {
    @MainActor
    static func present(items: [Any]) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController else {
            return nil
        }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }
}

private final class ShareHostController: UIViewController {
    var items: [Any] = []
    var onFinish: (() -> Void)?
    private var didPresent = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.onFinish?()
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(controller, animated: true)
    }
}

private struct ActivityShareSheetRepresentable: UIViewControllerRepresentable {
    let items: [Any]
    let dismiss: DismissAction

    func makeUIViewController(context: Context) -> ShareHostController {
        let controller = ShareHostController()
        controller.items = items
        controller.onFinish = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: ShareHostController, context: Context) {}
}
#endif

#if os(macOS)
private struct MacShareSheet: View {
    let items: [Any]
    let dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share")
                .font(.title2.bold())
            ShareLink(item: shareText) {
                Label("Copy or share exported files", systemImage: "square.and.arrow.up")
            }
            Button("Done") { dismiss() }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    private var shareText: String {
        items.compactMap { item -> String? in
            if let url = item as? URL { return url.path }
            if let string = item as? String { return string }
            return nil
        }
        .joined(separator: "\n")
    }
}
#endif
