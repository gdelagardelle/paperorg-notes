import Foundation
import StoreKit

@Observable
@MainActor
final class SubscriptionService {
    private let settings: SettingsService
    private let proBackend: ProBackendClient

    private(set) var products: [Product] = []
    private(set) var purchaseInProgress = false
    private(set) var lastError: String?
    private var updatesTask: Task<Void, Never>?

    init(settings: SettingsService, proBackend: ProBackendClient) {
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

    func loadProducts() async {
        do {
            products = try await Product.products(for: [SubscriptionProduct.proMonthly])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        do {
            let usage = try await proBackend.refreshUsage()
            applyUsageEntitlements(usage)
        } catch {
            lastError = error.localizedDescription
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
            lastError = "Subscription product unavailable. Try again later."
            return false
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handle(transaction: transaction)
                await transaction.finish()
                settings.selectedPlan = .pro
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase is pending approval."
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
                    await handle(transaction: transaction)
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
                    await handle(transaction: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    private func handle(transaction: Transaction) async {
        guard transaction.productID == SubscriptionProduct.proMonthly else { return }
        do {
            _ = try await proBackend.verifySubscription(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                signedTransactionInfo: nil
            )
            settings.selectedPlan = .pro
            settings.applyProEntitlements()
        } catch {
            lastError = error.localizedDescription
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
