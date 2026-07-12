import SwiftUI

struct PrivacyConsentView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var agreed = false
    
    var body: some View {
        @Bindable var settings = environment.settingsService
        
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.primary)
                
                Text(L10n.Privacy.title)
                    .font(.largeTitle.bold())
                
                Text(L10n.Privacy.intro)
                    .foregroundStyle(AppTheme.textSecondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    privacyRow(icon: "mic.fill", title: L10n.Privacy.rowLocalTitle, detail: L10n.Privacy.rowLocalDetail)
                    privacyRow(icon: "lock.fill", title: L10n.Privacy.rowControlTitle, detail: L10n.Privacy.rowControlDetail)
                    privacyRow(icon: "doc.text.fill", title: L10n.Privacy.rowGdprTitle, detail: L10n.Privacy.rowGdprDetail)
                    privacyRow(icon: "brain.head.profile", title: L10n.Privacy.rowProvidersTitle, detail: L10n.Privacy.rowProvidersDetail)
                }
                .cardStyle()
                
                Toggle(isOn: $agreed) {
                    Text(L10n.Privacy.agree)
                        .font(.subheadline)
                }
                .tint(AppTheme.primary)

                Text(L10n.Privacy.providerHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                
                Link(L10n.Privacy.viewPolicy, destination: URL(string: "https://gdelagardelle.github.io/paperorg-notes/privacy.html")!)
                    .font(.subheadline)
                
                Button(L10n.Privacy.continue) {
                    settings.hasAcceptedPrivacyPolicy = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!agreed)
            }
            .padding(24)
        }
        .background(AppTheme.background)
    }
    
    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

struct FaceIDLockView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isUnlocked: Bool
    @State private var errorMessage: String?
    @State private var showDisableLockOption = false
    @State private var isAuthenticating = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primary)
            
            Text(L10n.Lock.title)
                .font(.title2.bold())
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button(L10n.Lock.unlock) {
                requestAuthentication(force: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            .disabled(isAuthenticating)

            if showDisableLockOption {
                Button(L10n.Lock.disable) {
                    environment.settingsService.faceIDEnabled = false
                    isUnlocked = true
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .onAppear { requestAuthentication(force: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestAuthentication(force: false)
            }
        }
    }
    
    private func requestAuthentication(force: Bool) {
        guard !isUnlocked, scenePhase == .active else { return }
        guard force || !isAuthenticating else { return }
        authenticate()
    }
    
    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        LAContextWrapper.evaluate { success, error, canDisableLock in
            isAuthenticating = false
            if success {
                isUnlocked = true
                errorMessage = nil
                showDisableLockOption = false
            } else {
                errorMessage = error
                showDisableLockOption = canDisableLock
            }
        }
    }
}

import LocalAuthentication

enum LAContextWrapper {
    static func evaluate(completion: @escaping (Bool, String?, Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var policyError: NSError?
        let policy: LAPolicy

        switch context.biometryType {
        case .faceID, .touchID, .opticID:
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) {
                policy = .deviceOwnerAuthenticationWithBiometrics
            } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) {
                policy = .deviceOwnerAuthentication
            } else {
                let message = friendlyMessage(for: policyError)
                completion(false, message, true)
                return
            }
        default:
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) {
                policy = .deviceOwnerAuthentication
            } else {
                let message = friendlyMessage(for: policyError)
                completion(false, message, true)
                return
            }
        }

        context.evaluatePolicy(policy, localizedReason: "Unlock Paperorg Notes") { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil, false)
                } else {
                    let nsError = error as NSError?
                    let message = friendlyMessage(for: nsError)
                    completion(false, message, shouldOfferDisableLock(for: nsError))
                }
            }
        }
    }

    private static func friendlyMessage(for error: NSError?) -> String {
        guard let error else { return String(localized: "lock.error.generic") }

        switch laErrorCode(from: error) {
        case .biometryNotAvailable:
            return String(localized: "lock.error.biometry_unavailable")
        case .biometryNotEnrolled:
            return String(localized: "lock.error.biometry_not_enrolled")
        case .passcodeNotSet:
            return String(localized: "lock.error.passcode_not_set")
        case .userCancel, .systemCancel, .appCancel:
            return String(localized: "lock.error.cancelled")
        case .notInteractive:
            return String(localized: "lock.error.not_interactive")
        case .authenticationFailed:
            return String(localized: "lock.error.failed")
        default:
            return String(localized: "lock.error.generic")
        }
    }

    private static func shouldOfferDisableLock(for error: NSError?) -> Bool {
        guard let error else { return false }
        switch laErrorCode(from: error) {
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet, .biometryLockout:
            return true
        default:
            return false
        }
    }

    private static func laErrorCode(from error: NSError) -> LAError.Code? {
        if error.domain == LAError.errorDomain {
            if let code = LAError.Code(rawValue: error.code) {
                return code
            }
            if let code = LAError.Code(rawValue: -error.code) {
                return code
            }
            switch error.code {
            case 6: return .biometryNotAvailable
            case 7: return .biometryNotEnrolled
            case 5: return .passcodeNotSet
            default: break
            }
        }
        return nil
    }
}
