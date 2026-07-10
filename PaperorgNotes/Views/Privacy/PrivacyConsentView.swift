import SwiftUI

struct PrivacyConsentView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var agreed = false
    @State private var providerConsent = false
    
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

                Toggle(isOn: $providerConsent) {
                    Text("I allow Paperorg Notes to send audio and transcript text to my configured transcription and summary providers.")
                        .font(.subheadline)
                }
                .tint(AppTheme.primary)
                
                Link("View Privacy Policy", destination: URL(string: "https://gdelagardelle.github.io/paperorg-notes/privacy.html")!)
                    .font(.subheadline)
                
                Button("Continue") {
                    settings.hasAcceptedPrivacyPolicy = true
                    for provider in ProviderID.allCases {
                        settings.consentProvider(provider)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!agreed || !providerConsent)
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
    @Binding var isUnlocked: Bool
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primary)
            
            Text("Paperorg Notes is Locked")
                .font(.title2.bold())
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }
            
            Button("Unlock") {
                authenticate()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .onAppear { authenticate() }
    }
    
    private func authenticate() {
        LAContextWrapper.evaluate { success, error in
            if success {
                isUnlocked = true
            } else {
                errorMessage = error ?? "Authentication failed"
            }
        }
    }
}

import LocalAuthentication

enum LAContextWrapper {
    static func evaluate(completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false, error?.localizedDescription ?? "Device authentication is not available")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Paperorg Notes") { success, err in
            DispatchQueue.main.async {
                completion(success, err?.localizedDescription)
            }
        }
    }
}
