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

    #if DEBUG
    /// This entitlement exists only while a debug process is running under
    /// Xcode's local StoreKit test environment. It is deliberately not
    /// persisted, so a local test purchase can never become a TestFlight or
    /// production entitlement.
    private var xcodeStoreKitUsage: ProUsageInfo?
    #endif

    init(settings: SettingsService, proBackend: any SubscriptionVerifying) {
        self.settings = settings
        self.proBackend = proBackend
        updatesTask = listenForTransactions()
    }

    var isProActive: Bool {
        #if DEBUG
        if xcodeStoreKitUsage?.isPro == true {
            return true
        }
        #endif
        return settings.cachedProUsage?.isPro == true
    }

    var usageInfo: ProUsageInfo? {
        #if DEBUG
        if let xcodeStoreKitUsage {
            return xcodeStoreKitUsage
        }
        #endif
        return settings.cachedProUsage
    }

    var selectedPlan: SubscriptionPlan {
        get { settings.selectedPlan }
        set { settings.selectedPlan = newValue }
    }

    /// Loads the App Store product metadata used for the displayed price.
    /// A missing result is kept separate from a purchase verification failure:
    /// it means StoreKit did not return this product for the current storefront.
    func loadProducts(reportError: Bool = true) async {
        do {
            products = try await Product.products(for: [SubscriptionProduct.proMonthly])
            if products.isEmpty, reportError {
                lastError = L10n.Subscription.productUnavailable
            } else if !products.isEmpty {
                lastError = nil
            }
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
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let confirmed = await handle(transaction: transaction)
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
            lastError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result),
                   transaction.productID == SubscriptionProduct.proMonthly {
                    if await handle(transaction: transaction) {
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
                    if await handle(transaction: transaction) {
                        await transaction.finish()
                    }
                }
            }
        }
    }

    @discardableResult
    func handle(transaction: Transaction) async -> Bool {
        #if DEBUG
        if transaction.environment == .xcode {
            return grantXcodeStoreKitEntitlement(for: transaction.productID)
        }
        #endif
        return await confirmSubscription(
            productID: transaction.productID,
            transactionID: String(transaction.id)
        )
    }

    #if DEBUG
    /// Xcode's local StoreKit receipts are intentionally not known to Apple's
    /// App Store Server API. Keep that local-only path out of the backend and
    /// grant a process-scoped entitlement solely for testing purchase, restore,
    /// and Pro-gating UI. Release and TestFlight always use server verification.
    @discardableResult
    func grantXcodeStoreKitEntitlement(for productID: String) -> Bool {
        guard productID == SubscriptionProduct.proMonthly else { return false }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let periodStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? now
        let periodFormatter = DateFormatter()
        periodFormatter.locale = Locale(identifier: "en_US_POSIX")
        periodFormatter.dateFormat = "yyyy-MM"

        xcodeStoreKitUsage = ProUsageInfo(
            isPro: true,
            minutesLimit: 600,
            minutesUsed: 0,
            minutesRemaining: 600,
            periodKey: periodFormatter.string(from: periodStart),
            proExpiresAt: ISO8601DateFormatter().string(from: periodEnd)
        )
        settings.selectedPlan = .pro
        settings.applyProEntitlements()
        lastError = nil
        return true
    }
    #endif

    /// Pro stays locked until the backend has independently confirmed the
    /// StoreKit transaction with Apple. This prevents a successful sheet from
    /// being presented as an active entitlement when verification is unavailable.
    @discardableResult
    func confirmSubscription(productID: String, transactionID: String?) async -> Bool {
        guard productID == SubscriptionProduct.proMonthly else { return false }
        do {
            let usage = try await proBackend.verifySubscription(
                productID: productID,
                transactionID: transactionID,
                signedTransactionInfo: nil
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
            lastError = L10n.Subscription.verificationPending
            return false
        }
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
