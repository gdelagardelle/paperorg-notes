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
private struct ActivityShareSheetRepresentable: UIViewControllerRepresentable {
    let items: [Any]
    let dismiss: DismissAction

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
