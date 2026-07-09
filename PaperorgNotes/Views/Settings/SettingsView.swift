import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showDeleteConfirmation = false
    @State private var showProviderConsent: ProviderID?
    @State private var newEmail = ""
    @State private var openAIKey = ""
    @State private var elevenLabsKey = ""
    @State private var luxASRKey = ""
    @State private var newVocabularyTerm = ""
    
    var body: some View {
        @Bindable var settings = environment.settingsService
        
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Default Language", selection: $settings.defaultLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    Toggle("Auto-detect Language", isOn: $settings.autoDetectLanguage)
                }
                
                Section("Transcription") {
                    SecureField("OpenAI API Key", text: $openAIKey)
                        .textContentType(.password)
                        .onChange(of: openAIKey) { _, val in
                            settings.openAIAPIKey = val.isEmpty ? nil : val
                        }
                    
                    SecureField("ElevenLabs API Key", text: $elevenLabsKey)
                        .textContentType(.password)
                        .onChange(of: elevenLabsKey) { _, val in
                            settings.elevenLabsAPIKey = val.isEmpty ? nil : val
                        }
                    
                    SecureField("LuxASR API Key (optional)", text: $luxASRKey)
                        .textContentType(.password)
                        .onChange(of: luxASRKey) { _, val in
                            settings.luxASRAPIKey = val.isEmpty ? nil : val
                        }
                    
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                    .font(.subheadline)
                                Text(provider.sendsAudioOffDevice ? "Sends audio off-device" : "On-device only")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            if settings.isProviderConsented(provider) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.primary)
                            } else {
                                Button("Consent") {
                                    showProviderConsent = provider
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Vocabulary")
                            .font(.subheadline.bold())
                        Text("Names, brands, and terms to improve transcription accuracy.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    ForEach(settings.customVocabulary, id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button(role: .destructive) {
                                settings.removeVocabularyTerm(term)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Add term", text: $newVocabularyTerm)
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            settings.addVocabularyTerm(newVocabularyTerm)
                            newVocabularyTerm = ""
                        }
                        .disabled(newVocabularyTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Vocabulary")
                }
                
                Section("Output") {
                    Picker("Default Output Type", selection: $settings.defaultOutputType) {
                        ForEach(OutputType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("Summary Length", selection: $settings.summaryLength) {
                        ForEach(SummaryLength.allCases) { len in
                            Text(len.displayName).tag(len)
                        }
                    }
                }
                
                Section("Email") {
                    Picker("Policy", selection: $settings.emailPolicy) {
                        ForEach(EmailPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    
                    Picker("Content", selection: $settings.emailContent) {
                        ForEach(EmailContent.allCases) { content in
                            Text(content.displayName).tag(content)
                        }
                    }
                    
                    Toggle("Attach Audio", isOn: $settings.emailAttachAudio)
                    Toggle("Attach PDF", isOn: $settings.emailAttachPDF)
                    Toggle("Attach Markdown", isOn: $settings.emailAttachMarkdown)
                    Toggle("Review before send", isOn: $settings.reviewBeforeEmail)
                    
                    HStack {
                        TextField("Add email address", text: $newEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            guard !newEmail.isEmpty else { return }
                            var recipients = settings.emailRecipients
                            recipients.append(newEmail)
                            settings.emailRecipients = recipients
                            newEmail = ""
                        }
                    }
                    
                    ForEach(settings.emailRecipients, id: \.self) { email in
                        HStack {
                            Text(email)
                            Spacer()
                            Button(role: .destructive) {
                                settings.emailRecipients.removeAll { $0 == email }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                
                Section("Privacy & GDPR") {
                    Toggle("Keep Audio Files", isOn: $settings.keepAudioFiles)
                    Toggle("Delete Audio After Transcription", isOn: $settings.deleteAudioAfterTranscription)
                    
                    Button("Export All Data") {
                        _ = try? environment.storageService.exportGDPRArchive(notes: [])
                    }
                    
                    Button("Delete All Data", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
                
                Section("Security") {
                    Toggle("Face ID Lock", isOn: $settings.faceIDEnabled)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcription Providers")
                            .font(.subheadline.bold())
                        Text("Luxembourgish: LuxASR (primary) → ElevenLabs → OpenAI")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("Other languages: OpenAI (primary) → ElevenLabs")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadKeys() }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    environment.storageService.deleteAllAudio()
                    environment.settingsService.resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all notes, audio, transcripts, and API keys.")
            }
            .sheet(item: $showProviderConsent) { provider in
                ProviderConsentView(provider: provider)
            }
        }
    }
    
    private func loadKeys() {
        openAIKey = environment.settingsService.openAIAPIKey ?? ""
        elevenLabsKey = environment.settingsService.elevenLabsAPIKey ?? ""
        luxASRKey = environment.settingsService.luxASRAPIKey ?? ""
    }
}

extension ProviderID: Identifiable {
    var id: String { rawValue }
}

struct ProviderConsentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderID
    @State private var agreed = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(provider.displayName)
                        .font(.title2.bold())
                    
                    Label("Hosted in: \(provider.country)", systemImage: "globe")
                        .font(.subheadline)
                    
                    if provider.sendsAudioOffDevice {
                        Text("When you transcribe, your audio will be sent to \(provider.displayName) for processing. Review their privacy policy before continuing.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        Text("This provider processes audio on your device. No audio leaves your iPhone.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    Toggle("I allow sending audio to \(provider.displayName)", isOn: $agreed)
                    
                    Button("Confirm") {
                        environment.settingsService.consentProvider(provider)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!agreed && provider.sendsAudioOffDevice)
                }
                .padding()
            }
            .navigationTitle("Provider Consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
