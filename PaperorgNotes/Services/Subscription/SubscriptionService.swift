import Foundation
import StoreKit

@MainActor
protocol SubscriptionVerifying: AnyObject {
    func refreshUsage() async throws -> ProUsageInfo

    func verifySubscription(
        productID: String,
        transactionID: String?,
        signedTransactionInfo: String?
    ) async throws -> ProUsageInfo

    func devActivatePro() async throws -> ProUsageInfo
}

extension ProBackendClient: SubscriptionVerifying {}

@Observable
@MainActor
final class SubscriptionService {
    private let settings: SettingsService
    private let proBackend: any SubscriptionVerifying

    private(set) var products: [Product] = []
    private(set) var purchaseInProgress = false
    private(set) var lastError: String?
    private var updatesTask: Task<Void, Never>?

    init(settings: SettingsService, proBackend: any SubscriptionVerifying) {
        self.settings = settings
        self.proBackend = proBackend
        updatesTask = listenForTransactions()
    }

    var isProActive: Bool {
        settings.cachedProUsage?.isPro == true
    }

    var usageInfo: ProUsageInfo? {
        settings.cachedProUsage
    }

    var selectedPlan: SubscriptionPlan {
        get { settings.selectedPlan }
        set { settings.selectedPlan = newValue }
    }

    /// Loads the App Store product metadata used for the displayed price.
    ///
    /// StoreKit may not return a product until Apple's first-subscription
    /// review is complete. The paywall can still explain the offering during
    /// that transient state, so its initial load can be silent.
    func loadProducts(reportError: Bool = true) async {
        do {
            products = try await Product.products(for: [SubscriptionProduct.proMonthly])
        } catch {
            if reportError {
                lastError = error.localizedDescription
            }
        }
    }

    /// Refreshes the server-side usage record.
    ///
    /// A new device has no access token until it registers. That is normal while
    /// the paywall is opening, so callers can opt out of treating a transient
    /// refresh failure as a purchase error.
    func refreshEntitlements(reportError: Bool = true) async {
        do {
            let usage = try await proBackend.refreshUsage()
            settings.cachedProUsage = usage
            applyUsageEntitlements(usage)
        } catch {
            if reportError {
                lastError = error.localizedDescription
            }
        }
    }

    private func applyUsageEntitlements(_ usage: ProUsageInfo) {
        if usage.isPro {
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
        } else if settings.selectedPlan == .pro {
            // A lapsed or unverified Pro selection must not block the free
            // included-minutes path on the next refresh.
            settings.selectedPlan = .free
        }
    }

    func purchasePro() async -> Bool {
        guard let product = products.first else {
            lastError = L10n.Subscription.productUnavailable
            return false
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await purchase(product)
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let confirmed = await handle(
                    transaction: transaction,
                    signedTransactionInfo: signedTransactionInfo(from: verification)
                )
                if confirmed {
                    await transaction.finish()
                }
                return confirmed
            case .userCancelled:
                return false
            case .pending:
                lastError = L10n.Subscription.purchasePending
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = Self.friendlyPurchaseError(for: error)
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result),
                   transaction.productID == SubscriptionProduct.proMonthly {
                    if await handle(
                        transaction: transaction,
                        signedTransactionInfo: signedTransactionInfo(from: result)
                    ) {
                        await transaction.finish()
                    }
                }
            }
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    #if DEBUG
    func activateDevPro() async {
        do {
            let usage = try await proBackend.devActivatePro()
            applyUsageEntitlements(usage)
            lastError = nil
        } catch {
            lastError = Self.friendlyErrorMessage(for: error)
        }
    }

    private static func friendlyErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError,
           urlError.code == .cannotConnectToHost || urlError.code == .networkConnectionLost {
            return "Backend not running. In Terminal run: ./Scripts/start-dev.sh"
        }
        if let backend = error as? ProBackendError,
           case .serverError(let message) = backend,
           message.localizedCaseInsensitiveContains("dev activation is disabled") {
            return "Dev Pro is off on this server. Use a local backend (./Scripts/start-dev.sh) or grant Pro in Console."
        }
        return error.localizedDescription
    }
    #endif

    private func listenForTransactions() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                if let transaction = try? checkVerified(result) {
                    if await handle(
                        transaction: transaction,
                        signedTransactionInfo: signedTransactionInfo(from: result)
                    ) {
                        await transaction.finish()
                    }
                }
            }
        }
    }

    @discardableResult
    private func handle(
        transaction: Transaction,
        signedTransactionInfo: String?
    ) async -> Bool {
        await confirmSubscription(
            productID: transaction.productID,
            transactionID: String(transaction.id),
            signedTransactionInfo: signedTransactionInfo
        )
    }

    /// Pro stays locked until the backend has independently confirmed the
    /// StoreKit transaction with Apple. This prevents a successful sheet from
    /// being presented as an active entitlement when verification is unavailable.
    @discardableResult
    func confirmSubscription(
        productID: String,
        transactionID: String?,
        signedTransactionInfo: String? = nil
    ) async -> Bool {
        guard productID == SubscriptionProduct.proMonthly else { return false }
        do {
            let usage = try await proBackend.verifySubscription(
                productID: productID,
                transactionID: transactionID,
                signedTransactionInfo: signedTransactionInfo
            )
            guard usage.isPro else {
                lastError = L10n.Subscription.entitlementUnavailable
                return false
            }
            settings.cachedProUsage = usage
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
            lastError = nil
            return true
        } catch {
            lastError = Self.friendlyVerificationError(for: error)
            return false
        }
    }

    private func signedTransactionInfo(from result: VerificationResult<Transaction>) -> String? {
        switch result {
        case .verified:
            return result.jwsRepresentation
        case .unverified:
            return nil
        }
    }

    private static func friendlyVerificationError(for error: Error) -> String {
        if let message = backendServerMessage(from: error), !message.isEmpty {
            if message.localizedCaseInsensitiveContains("transaction not found") {
                return "Your purchase went through, but the server has not matched it yet. Tap Restore Purchases, wait a minute, then Refresh Status."
            }
            if message.localizedCaseInsensitiveContains("missing metadata")
                || message.localizedCaseInsensitiveContains("not available for purchase") {
                return "Pro subscription setup is still incomplete in App Store Connect. Free included minutes still work — cancel here and use Continue Free in Settings."
            }
            return "Your purchase is complete, but Pro could not be activated yet: \(message)"
        }
        return L10n.Subscription.verificationPending
    }

    private static func backendServerMessage(from error: Error) -> String? {
        if case ProBackendError.serverError(let message) = error {
            return message
        }
        return nil
    }

    private func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        #if canImport(UIKit)
        if #available(iOS 18.2, *) {
            guard let viewController = PurchasePresenter.topViewController() else {
                throw PurchasePresentationError.missingViewController
            }
            return try await product.purchase(confirmIn: viewController)
        }
        #endif
        return try await product.purchase()
    }

    private static func friendlyPurchaseError(for error: Error) -> String {
        if error is PurchasePresentationError {
            return "The App Store sheet could not open. Close any open sheets and try again."
        }
        let nsError = error as NSError
        if nsError.domain == "SKInternalErrorDomain" {
            return "The App Store could not complete the purchase. Try again in a moment, or restart the app. If this keeps happening, check that you are signed into the App Store."
        }
        return error.localizedDescription
    }

    private enum PurchasePresentationError: Error {
        case missingViewController
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw ProBackendError.serverError("Purchase could not be verified.")
        }
    }
}
