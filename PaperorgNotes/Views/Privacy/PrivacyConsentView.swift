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
                
                Text("Your Privacy Matters")
                    .font(.largeTitle.bold())
                
                Text("Paperorg Notes records audio on your device. When you transcribe, audio may be sent to third-party services you configure (OpenAI, ElevenLabs, LuxASR).")
                    .foregroundStyle(AppTheme.textSecondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    privacyRow(icon: "mic.fill", title: "Local Recording", detail: "Audio is saved on your device first.")
                    privacyRow(icon: "lock.fill", title: "Your Control", detail: "You choose providers and can delete all data anytime.")
                    privacyRow(icon: "doc.text.fill", title: "GDPR", detail: "Export or delete all your data from Settings.")
                    privacyRow(icon: "brain.head.profile", title: "Provider Terms", detail: "Your data is handled according to each provider's terms and your configured account settings.")
                }
                .cardStyle()
                
                Toggle(isOn: $agreed) {
                    Text("I understand and agree to the Privacy Policy")
                        .font(.subheadline)
                }
                .tint(AppTheme.primary)

                Text("Provider consent is requested separately for each transcription provider in Settings before audio is sent off-device.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                
                Link("View Privacy Policy", destination: URL(string: "https://gdelagardelle.github.io/paperorg-notes/privacy.html")!)
                    .font(.subheadline)
                
                Button("Continue") {
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
            
            Text("Paperorg Notes is Locked")
                .font(.title2.bold())
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Unlock") {
                requestAuthentication(force: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            .disabled(isAuthenticating)

            if showDisableLockOption {
                Button("Turn Off Face ID Lock") {
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
        guard let error else { return "Authentication failed. Try again." }

        switch laErrorCode(from: error) {
        case .biometryNotAvailable:
            return "Face ID is not available on this device. Use your device passcode, or turn off Face ID lock."
        case .biometryNotEnrolled:
            return "Face ID is not set up on this device. Enroll Face ID in iOS Settings, or turn off Face ID lock."
        case .passcodeNotSet:
            return "Set a device passcode in iOS Settings to use app lock, or turn off Face ID lock."
        case .userCancel, .systemCancel, .appCancel:
            return "Unlock cancelled. Tap Unlock to try again."
        case .notInteractive:
            return "Face ID will appear when the app is active. Tap Unlock to try again."
        case .authenticationFailed:
            return "Authentication failed. Try again."
        default:
            return "Could not unlock Paperorg Notes. Try again or turn off Face ID lock."
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
