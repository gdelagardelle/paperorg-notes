import SwiftUI
import StoreKit

struct PlanSelectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Plan.chooseTitle)
                        .font(.largeTitle.bold())
                    Text(L10n.Plan.chooseSubtitle)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                planCard(
                    plan: .free,
                    price: L10n.Plan.freePrice,
                    features: [
                        String(localized: "plan.free.feature.record"),
                        String(localized: "plan.free.feature.openai"),
                        String(localized: "plan.free.feature.elevenlabs"),
                        String(localized: "plan.free.feature.vocabulary")
                    ],
                    buttonTitle: L10n.Plan.continueFree,
                    accent: AppTheme.primary
                ) {
                    environment.settingsService.selectedPlan = .free
                    environment.settingsService.hasCompletedPlanSelection = true
                }

                planCard(
                    plan: .pro,
                    price: proPriceLabel,
                    features: [
                        String(localized: "plan.pro.feature.minutes"),
                        String(localized: "plan.pro.feature.no_keys"),
                        String(localized: "plan.pro.feature.luxembourgish"),
                        String(localized: "plan.pro.feature.retention")
                    ],
                    buttonTitle: L10n.Plan.getPro,
                    accent: AppTheme.accent
                ) {
                    showPaywall = true
                }
            }
            .padding(24)
        }
        .background(AppScreenBackground())
        .task {
            await environment.subscriptionService.loadProducts()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onCompleted: {
                environment.settingsService.hasCompletedPlanSelection = true
                showPaywall = false
            })
        }
    }

    private var proPriceLabel: String {
        if let product = environment.subscriptionService.products.first {
            return "\(product.displayPrice)/month"
        }
        return L10n.Plan.proFallbackPrice
    }

    @ViewBuilder
    private func planCard(
        plan: SubscriptionPlan,
        price: String,
        features: [String],
        buttonTitle: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName)
                        .font(.title3.bold())
                    Text(plan.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Text(price)
                    .font(.headline)
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .symbolRenderingMode(.hierarchical)
                        .tint(accent)
                }
            }

            Button(buttonTitle, action: action)
                .buttonStyle(plan == .pro ? AnyButtonStyle(accent: true) : AnyButtonStyle(accent: false))
        }
        .surfaceCard()
    }
}

private struct AnyButtonStyle: ButtonStyle {
    let accent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if accent {
            AccentButtonStyle().makeBody(configuration: configuration)
        } else {
            SecondaryButtonStyle().makeBody(configuration: configuration)
        }
    }
}

struct PaywallView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    var onCompleted: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paperorg Pro")
                            .font(.largeTitle.bold())
                        Text("Transcription and AI summaries included — no OpenAI or ElevenLabs setup.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        featureRow("600 minutes per month included")
                        featureRow("Luxembourgish priority transcription")
                        featureRow("All note styles and languages")
                        featureRow("Automatic email after transcription")
                        featureRow("Unlimited custom vocabulary")
                        featureRow("Extended audio retention")
                    }
                    .surfaceCard()

                    if let usage = environment.subscriptionService.usageInfo, usage.isPro {
                        Label(
                            "\(Int(usage.minutesRemaining)) minutes remaining this month",
                            systemImage: "clock.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primary)
                    }

                    if let error = environment.subscriptionService.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                    }

                    #if DEBUG
                    Button {
                        Task {
                            await environment.subscriptionService.activateDevPro()
                            if environment.subscriptionService.isProActive {
                                onCompleted?()
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Try Pro Free (Simulator)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle())
                    #endif

                    Button {
                        Task {
                            let success = await environment.subscriptionService.purchasePro()
                            if success {
                                onCompleted?()
                                dismiss()
                            }
                        }
                    } label: {
                        if environment.subscriptionService.purchaseInProgress {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(purchaseButtonTitle)
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(environment.subscriptionService.purchaseInProgress)

                    Button("Restore Purchases") {
                        Task { await environment.subscriptionService.restorePurchases() }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if environment.settingsService.usePlatformAuth,
                       !environment.subscriptionService.isProActive {
                        Button("Refresh Status") {
                            Task { await environment.subscriptionService.refreshEntitlements() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Text("Subscription renews monthly. Cancel anytime in App Store settings.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(24)
            }
            .background(AppScreenBackground())
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await environment.subscriptionService.loadProducts()
                try? await environment.proBackendClient.ensureRegistered()
                await environment.subscriptionService.refreshEntitlements()
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let product = environment.subscriptionService.products.first {
            return "Subscribe for \(product.displayPrice)/month"
        }
        return "Subscribe to Pro"
    }

    private func featureRow(_ text: String) -> some View {
        Label(text, systemImage: "sparkles")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textPrimary)
    }
}
