import StoreKit
import StoreKitTest
import SwiftUI
import XCTest
@testable import PaperorgNotes

@MainActor
final class ThemeReadabilityTests: XCTestCase {
    func testButtonSpeakerAndLinkContrastInBothThemes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            func color(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: traits) }
            XCTAssertGreaterThanOrEqual(contrast(color(AppTheme.onFilled), color(AppTheme.filledPrimary)), 4.5, "Primary button: \(style)")
            XCTAssertGreaterThanOrEqual(contrast(color(AppTheme.onAccent), color(AppTheme.accent)), 4.5, "Accent button: \(style)")
            for (index, speaker) in AppTheme.speakerColors.enumerated() {
                for background in [AppTheme.surface, AppTheme.background] {
                    XCTAssertGreaterThanOrEqual(contrast(color(speaker), color(background)), 4.5, "Speaker \(index): \(style)")
                }
            }
            XCTAssertGreaterThanOrEqual(contrast(color(AppTheme.accentText), color(AppTheme.background)), 4.5, "Privacy link text: \(style)")
            let accent = try XCTUnwrap(UIColor(named: "AccentColor", in: .main, compatibleWith: traits))
            XCTAssertGreaterThanOrEqual(contrast(accent.resolvedColor(with: traits), color(AppTheme.background)), 4.5, "Default link: \(style)")
        }
    }

    func testRenderedSelectedChipRemainsReadableInBothThemes() throws {
        for scheme in [ColorScheme.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            var renderingResult: Result<Void, Error>!
            traits.performAsCurrent {
                renderingResult = Result {
                    let renderer = ImageRenderer(content: SelectionChip(title: "English", icon: "checkmark", isSelected: true, action: {})
                        .environment(\.colorScheme, scheme))
                    renderer.scale = 3
                    let rendered = try XCTUnwrap(renderer.uiImage)
                    let attachment = XCTAttachment(image: rendered)
                    attachment.name = "Selected chip \(scheme)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    let cgImage = try XCTUnwrap(rendered.cgImage)
                    var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
                    let context = try XCTUnwrap(CGContext(data: &pixels, width: cgImage.width, height: cgImage.height,
                        bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                    let luminances = stride(from: 0, to: pixels.count, by: 4).compactMap { index -> Double? in
                        guard pixels[index + 3] == 255 else { return nil }
                        return luminance(UIColor(red: CGFloat(pixels[index]) / 255, green: CGFloat(pixels[index + 1]) / 255,
                            blue: CGFloat(pixels[index + 2]) / 255, alpha: 1))
                    }
                    let ratio = (try XCTUnwrap(luminances.max()) + 0.05) / (try XCTUnwrap(luminances.min()) + 0.05)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "Rendered selected chip: \(scheme)")
                }
            }
            try renderingResult.get()
        }
    }

    func testRenderSharedControlsForVisualReview() throws {
        for scheme in [ColorScheme.light, .dark] {
            let segments = (0..<4).map { index in
                TranscriptSegmentModel(from: TranscriptSegmentDTO(index: index, text: "A clear transcript, ready to review.",
                    startTime: Double(index * 5), endTime: Double(index * 5 + 4), confidence: 1, speakerLabel: "SPEAKER_0\(index)"))
            }
            let view = VStack(alignment: .leading, spacing: 18) {
                Text("Paperorg Notes").font(.title.bold()).foregroundStyle(AppTheme.textPrimary)
                HStack {
                    SelectionChip(title: "English", icon: "checkmark", isSelected: true, action: {})
                    SelectionChip(title: "Français", isSelected: false, action: {})
                    FilterChip(title: "All notes", isSelected: true, action: {})
                }
                Button("Continue", action: {}).buttonStyle(PrimaryButtonStyle())
                Button("Start recording", action: {}).buttonStyle(AccentButtonStyle())
                VStack(spacing: 12) {
                    ForEach(segments) { segment in
                        SegmentRow(segment: segment, isPlaying: segment.segmentIndex == 1, onPlay: {}, onEdit: {})
                    }
                }.surfaceCard()
                Link("Privacy policy", destination: URL(string: "https://gdelagardelle.github.io/paperorg-notes/privacy.html")!)
                    .tint(AppTheme.accentText)
            }
            .padding(24)
            .frame(width: 420)
            .background(AppTheme.background)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "Shared controls \(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

@MainActor
final class StoreKitRecoveryTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "PaperorgPro")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.timeRate = .realTime
        return session
    }

    func testRestoreRequestsFreshAppStoreSyncAndReportsItsFailure() async throws {
        let session = try session()
        defer { session.resetToDefaultState(); session.clearTransactions() }
        let error = StoreKitError.networkError(URLError(.notConnectedToInternet))
        try await session.setSimulatedError(.generic(error), forAPI: .appStoreSync)
        let (settings, service) = makeService()
        await service.restorePurchases()
        XCTAssertFalse(settings.storeKitProTrusted)
        // StoreKit Test wraps the injected network failure in an internal
        // App Store error. It must reach the localized purchase error path.
        XCTAssertEqual(service.lastError, L10n.Subscription.purchaseUnavailable)
    }

    func testRestoreRecoversExistingPurchaseWhileServerIsOffline() async throws {
        let session = try session()
        defer { session.resetToDefaultState(); session.clearTransactions() }
        _ = try await session.buyProduct(identifier: SubscriptionProduct.proMonthly)
        let (settings, service) = makeService()
        XCTAssertFalse(settings.storeKitProTrusted)
        await service.restorePurchases()
        XCTAssertTrue(settings.storeKitProTrusted)
        XCTAssertTrue(service.isProActive)
        XCTAssertTrue(service.isProPendingServerConfirmation)
        XCTAssertNil(service.lastError)
    }

    func testRefundUpdateClearsLocallyTrustedProWithoutManualRefresh() async throws {
        let session = try session()
        defer { session.resetToDefaultState(); session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: SubscriptionProduct.proMonthly)
        let (settings, service) = makeService()
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertNotNil(transaction.expirationDate)
        var active = await service.refreshStoreKitProStatus()
        let activationDeadline = Date().addingTimeInterval(5)
        while !active && Date() < activationDeadline {
            try await Task.sleep(for: .milliseconds(100))
            active = await service.refreshStoreKitProStatus()
        }
        for await result in Transaction.currentEntitlements {
            if case .unverified(_, let error) = result { XCTFail("StoreKit fixture verification: \(error)") }
        }
        XCTAssertTrue(active)
        XCTAssertTrue(service.isProActive)
        try session.refundTransaction(identifier: UInt(transaction.id))
        let deadline = Date().addingTimeInterval(5)
        while service.isProActive && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(settings.storeKitProTrusted)
        XCTAssertFalse(service.isProActive)
        XCTAssertEqual(settings.selectedPlan, .free)
    }

    private func makeService() -> (SettingsService, SubscriptionService) {
        let suite = "StoreKitRecoveryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(keychain: KeychainService(), defaults: defaults)
        return (settings, SubscriptionService(settings: settings, proBackend: UnavailableVerifier(), loadStoreKitEntitlementsOnLaunch: false))
    }
}

@MainActor
private final class UnavailableVerifier: SubscriptionVerifying {
    func refreshUsage() async throws -> ProUsageInfo { throw URLError(.notConnectedToInternet) }
    func verifySubscription(productID: String, transactionID: String?, signedTransactionInfo: String?) async throws -> ProUsageInfo {
        throw URLError(.notConnectedToInternet)
    }
    func devActivatePro() async throws -> ProUsageInfo { throw URLError(.notConnectedToInternet) }
}
