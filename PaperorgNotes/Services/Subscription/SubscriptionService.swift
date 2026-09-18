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
    private var backgroundConfirmationTask: Task<Void, Never>?

    init(settings: SettingsService, proBackend: any SubscriptionVerifying) {
        self.settings = settings
        self.proBackend = proBackend
        updatesTask = listenForTransactions()
        Task { await refreshStoreKitProStatus() }
    }

    var isProActive: Bool {
        isServerProActive || settings.storeKitProTrusted
    }

    var usageInfo: ProUsageInfo? {
        settings.cachedProUsage
    }

    var selectedPlan: SubscriptionPlan {
        get { settings.selectedPlan }
        set { settings.selectedPlan = newValue }
    }

    private var isServerProActive: Bool {
        settings.cachedProUsage?.isPro == true
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
        await refreshStoreKitProStatus()
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
            settings.storeKitProTrusted = true
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
        } else if settings.selectedPlan == .pro, !settings.storeKitProTrusted {
            // A lapsed or unverified Pro selection must not block the free
            // included-minutes path on the next refresh.
            settings.selectedPlan = .free
        }
    }

    func purchasePro() async -> Bool {
        await refreshStoreKitProStatus()
        if isProActive {
            lastError = nil
            scheduleBackgroundServerConfirmation()
            return true
        }

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
                let signedInfo = signedTransactionInfo(from: verification)
                applyStoreKitProTrust()
                scheduleBackgroundServerConfirmation(
                    transaction: transaction,
                    signedTransactionInfo: signedInfo
                )
                return true
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

    /// Re-checks local StoreKit entitlements and confirms Pro with Platform.
    /// Does not call `AppStore.sync()` — that prompts for an App Store password.
    @discardableResult
    func syncEntitlementsFromStore(reportError: Bool = true) async -> Bool {
        await refreshStoreKitProStatus()
        var confirmedAny = false
        for await result in Transaction.unfinished {
            if await processEntitlement(result) {
                confirmedAny = true
            }
        }
        for await result in Transaction.currentEntitlements {
            if await processEntitlement(result) {
                confirmedAny = true
            }
        }
        if isProActive {
            lastError = nil
            return true
        }
        await refreshEntitlements(reportError: false)
        if isProActive {
            lastError = nil
            return true
        }
        if !confirmedAny, reportError, lastError == nil {
            lastError = L10n.Subscription.entitlementUnavailable
        }
        return isProActive
    }

    func restorePurchases() async {
        _ = await syncEntitlementsFromStore()
    }

    /// Best-effort Platform confirmation before cloud transcription when Pro is
    /// trusted locally from StoreKit but the server has not caught up yet.
    func ensureServerProConfirmedBeforeProcessing() async {
        guard settings.storeKitProTrusted, !isServerProActive else { return }
        _ = await syncEntitlementsFromStore(reportError: false)
    }

    @discardableResult
    func refreshStoreKitProStatus() async -> Bool {
        let active = await hasActiveStoreKitProEntitlement()
        settings.storeKitProTrusted = active
        if active {
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
        } else if !isServerProActive {
            settings.storeKitProTrusted = false
        }
        return active
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
                _ = await processEntitlement(result)
            }
        }
    }

    @discardableResult
    private func processEntitlement(_ result: VerificationResult<Transaction>) async -> Bool {
        guard let transaction = try? checkVerified(result),
              transaction.productID == SubscriptionProduct.proMonthly else {
            return false
        }
        applyStoreKitProTrust()
        let confirmed = await confirmSubscription(
            productID: transaction.productID,
            transactionID: String(transaction.id),
            signedTransactionInfo: signedTransactionInfo(from: result)
        )
        if confirmed {
            await transaction.finish()
        }
        return confirmed || settings.storeKitProTrusted
    }

    private func scheduleBackgroundServerConfirmation(
        transaction: Transaction? = nil,
        signedTransactionInfo: String? = nil
    ) {
        backgroundConfirmationTask?.cancel()
        backgroundConfirmationTask = Task {
            if let transaction {
                if await confirmWithRetries(
                    transaction: transaction,
                    signedTransactionInfo: signedTransactionInfo
                ) {
                    await transaction.finish()
                }
                return
            }
            _ = await syncEntitlementsFromStore(reportError: false)
        }
    }

    private func confirmWithRetries(
        transaction: Transaction,
        signedTransactionInfo: String?
    ) async -> Bool {
        let retryDelaysNanoseconds: [UInt64] = [0, 1_000_000_000, 2_000_000_000, 4_000_000_000, 8_000_000_000]
        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            if await confirmSubscription(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                signedTransactionInfo: signedTransactionInfo
            ) {
                return true
            }
            await refreshEntitlements(reportError: false)
            if isServerProActive {
                return true
            }
        }
        return false
    }

    private func applyStoreKitProTrust() {
        settings.storeKitProTrusted = true
        settings.selectedPlan = .pro
        settings.applyProEntitlements()
        lastError = nil
    }

    private func hasActiveStoreKitProEntitlement() async -> Bool {
        for await result in Transaction.unfinished {
            if isProEntitlement(result) { return true }
        }
        for await result in Transaction.currentEntitlements {
            if isProEntitlement(result) { return true }
        }
        return false
    }

    private func isProEntitlement(_ result: VerificationResult<Transaction>) -> Bool {
        guard let transaction = try? checkVerified(result) else { return false }
        return transaction.productID == SubscriptionProduct.proMonthly
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
            settings.storeKitProTrusted = true
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
            lastError = nil
            return true
        } catch {
            if settings.storeKitProTrusted {
                // Keep Pro unlocked locally; background retries continue elsewhere.
                return false
            }
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
            if message.localizedCaseInsensitiveContains("signed transaction data is not accepted") {
                return "Pro is activating. Update to the latest TestFlight build, then tap Subscribe again."
            }
            if message.localizedCaseInsensitiveContains("transaction not found") {
                return "Pro is activating. You can use the app now; server confirmation may take a moment."
            }
            if message.localizedCaseInsensitiveContains("missing metadata")
                || message.localizedCaseInsensitiveContains("not available for purchase") {
                return "Pro subscription setup is still incomplete in App Store Connect. Free included minutes still work — cancel here and use Continue Free in Settings."
            }
            return "Pro is activating. You can use the app now. (\(message))"
        }
        return "Pro is activating. You can use the app now."
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
