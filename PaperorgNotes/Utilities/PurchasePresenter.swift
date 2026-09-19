#if canImport(UIKit)
import UIKit

enum PurchasePresenter {
    /// Topmost view controller for StoreKit purchase confirmation (iOS 18.2+).
    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let keyWindow = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)

        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
