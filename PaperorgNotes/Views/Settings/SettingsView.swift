import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var showDeleteConfirmation = false
    @State private var showProviderConsent: ProviderID?
    @State private var newEmail = ""
    @State private var emailValidationMessage: String?
    @State private var openAIKey = ""
    @State private var elevenLabsKey = ""
    @State private var luxASRKey = ""
    @State private var smtpPassword = ""
    @State private var newVocabularyTerm = ""
    @State private var gdprExportURL: URL?
    @State private var showGDPRExportShare = false
    @State private var gdprExportError: String?
    @State private var showPaywall = false
    
    var body: some View {
        @Bindable var settings = environment.settingsService
        
        NavigationStack {
            Form {
                Section(L10n.Settings.proSection) {
                    if environment.subscriptionService.isProActive {
                        Label(L10n.Settings.proActive, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(AppTheme.accent)
                        if let usage = environment.subscriptionService.usageInfo {
                            ProUsageCard(usage: usage) {
                                Task { await environment.subscriptionService.refreshEntitlements() }
                            }
                        }
                        SettingsSectionHint(text: L10n.Settings.proHint)
                    } else if settings.selectedPlan == .pro {
                        Text(L10n.Settings.proSelected)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                        Button(L10n.Settings.subscribePro) { showPaywall = true }
                    } else {
                        SettingsSectionHint(text: String(localized: "settings.free.hint"))
                        Button(L10n.Settings.upgradePro) { showPaywall = true }
                    }
                }

                if environment.subscriptionService.isProActive {
                    ExportBrandingSettingsSection()
                }

                Section(L10n.Settings.languageSection) {
                    Picker(L10n.Settings.defaultLanguage, selection: $settings.defaultLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                }
                
                Section {
                    if environment.subscriptionService.isProActive {
                        SettingsSectionHint(text: "Your Pro plan includes cloud transcription through Paperorg's secure backend.")
                    } else {
                        SettingsSectionHint(text: "Free plan: add your OpenAI API key below (required). ElevenLabs is recommended for Lëtzebuergesch.")
                    }

                    if !environment.subscriptionService.isProActive {
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
                    }
                    if !environment.subscriptionService.isProActive {
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
                                    Button("Revoke") {
                                        settings.revokeProviderConsent(provider)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.error)
                                } else {
                                    Button("Consent") {
                                        showProviderConsent = provider
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                } header: {
                    Text(L10n.Settings.transcriptionSection)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Vocabulary")
                            .font(.subheadline.bold())
                        Text("Names, brands, and terms to improve transcription accuracy.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        if !environment.subscriptionService.isProActive {
                            Text("Free plan: up to \(settings.freeVocabularyLimit) terms. Pro includes unlimited vocabulary.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
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
                        .disabled(
                            newVocabularyTerm.trimmingCharacters(in: .whitespaces).isEmpty
                            || (!environment.subscriptionService.isProActive
                                && settings.customVocabulary.count >= settings.freeVocabularyLimit)
                        )
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
                    Toggle("Send email after transcription", isOn: $settings.sendEmailAfterTranscription)
                    if settings.sendEmailAfterTranscription {
                        SettingsSectionHint(text: "Paperorg sends your note by email automatically when transcription finishes — no mail setup on your phone. Just add who should receive it below.")
                        if settings.useOwnMailServerForEmail && !settings.isAutomaticEmailConfigured {
                            Text("Finish your own mail server setup below, or turn that option off to let Paperorg send for you.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.error)
                        }
                    }

                    HStack {
                        TextField("Add email address", text: $newEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            addRecipient()
                        }
                        .disabled(newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let emailValidationMessage {
                        Text(emailValidationMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                    }

                    ForEach(settings.emailRecipients, id: \.self) { email in
                        HStack {
                            Text(email)
                            Spacer()
                            Button(role: .destructive) {
                                settings.emailRecipients = settings.emailRecipients.filter { $0 != email }
                            } label: {
                                Image(systemName: "trash")
                            }
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
                    if settings.reviewBeforeEmail {
                        SettingsSectionHint(text: "Only applies when you tap Send Email on a note. Automatic post-recording email always sends without review.")
                    }

                    DisclosureGroup("Advanced: send from my own email") {
                        Toggle("Use my own mail server", isOn: $settings.useOwnMailServerForEmail)

                        if settings.useOwnMailServerForEmail {
                            Picker("Mail provider", selection: $settings.smtpProviderPreset) {
                                ForEach(SMTPProviderPreset.allCases.filter { $0 != .custom }) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                                Text(SMTPProviderPreset.custom.displayName).tag(SMTPProviderPreset.custom)
                            }
                            .onChange(of: settings.smtpProviderPreset) { _, preset in
                                if preset != .custom {
                                    settings.applySMTPPreset(preset)
                                }
                            }

                            SettingsSectionHint(text: settings.smtpProviderPreset.setupHint)

                            TextField("From address", text: $settings.smtpFromAddress)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .onChange(of: settings.smtpFromAddress) { _, value in
                                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if settings.smtpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                       !trimmed.isEmpty {
                                        settings.smtpUsername = trimmed
                                    }
                                }

                            if settings.smtpProviderPreset == .custom {
                                TextField("SMTP host", text: $settings.smtpHost)
                                    .textInputAutocapitalization(.never)

                                Stepper("Port: \(settings.smtpPort)", value: $settings.smtpPort, in: 1...65535)
                            }

                            TextField("Email username", text: $settings.smtpUsername)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)

                            SecureField("App password", text: $smtpPassword)
                                .textContentType(.password)
                                .onChange(of: smtpPassword) { _, value in
                                    settings.smtpPassword = value.isEmpty ? nil : value
                                }
                        } else {
                            SettingsSectionHint(text: "Recommended for most people. Paperorg handles delivery — works with any recipient inbox (Apple Mail, Outlook, Gmail, etc.).")
                        }
                    }
                }
                
                Section("Privacy & GDPR") {
                    Toggle("Keep Audio Files", isOn: $settings.keepAudioFiles)
                    if settings.keepAudioFiles {
                        Toggle("Delete Audio After Transcription", isOn: $settings.deleteAudioAfterTranscription)
                        if settings.deleteAudioAfterTranscription {
                            SettingsSectionHint(text: "Audio is removed as soon as transcription completes.")
                        } else {
                            Picker("Delete Audio After", selection: Binding(
                                get: { settings.deleteAudioAfterDays ?? 0 },
                                set: { settings.deleteAudioAfterDays = $0 == 0 ? nil : $0 }
                            )) {
                                Text("Never").tag(0)
                                Text("7 days").tag(7)
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                            }
                        }
                    } else {
                        SettingsSectionHint(text: "Audio is removed after transcription. Retention options are unavailable.")
                    }
                    
                    Button("Export All Data") {
                        exportAllData()
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
            .listStyle(.insetGrouped)
            .settingsScreenStyle()
            .navigationTitle(L10n.Settings.title)
            .onAppear {
                loadKeys()
                environment.storageService.purgeExpiredAudio(
                    notes: notes,
                    retentionDays: environment.settingsService.effectiveAudioRetentionDays
                )
                try? modelContext.save()
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    try? environment.deleteNoteUseCase.deleteAllNotes(notes, context: modelContext)
                    environment.storageService.deleteAllLocalData()
                    environment.settingsService.resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all notes, audio, transcripts, and API keys.")
            }
            .sheet(item: $showProviderConsent) { provider in
                ProviderConsentView(provider: provider)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showGDPRExportShare) {
                if let gdprExportURL {
                    ActivityShareSheet(items: [gdprExportURL])
                }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { gdprExportError != nil },
                set: { if !$0 { gdprExportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(gdprExportError ?? "")
            }
        }
    }
    
    private func exportAllData() {
        do {
            gdprExportURL = try environment.storageService.exportGDPRArchive(notes: notes)
            showGDPRExportShare = true
        } catch {
            gdprExportError = error.localizedDescription
        }
    }
    
    private func loadKeys() {
        openAIKey = environment.settingsService.openAIAPIKey ?? ""
        elevenLabsKey = environment.settingsService.elevenLabsAPIKey ?? ""
        luxASRKey = environment.settingsService.luxASRAPIKey ?? ""
        smtpPassword = environment.settingsService.smtpPassword ?? ""
        if environment.settingsService.sendEmailAfterTranscription,
           environment.settingsService.smtpHost.isEmpty,
           environment.settingsService.smtpProviderPreset != .custom {
            environment.settingsService.applySMTPPreset(environment.settingsService.smtpProviderPreset)
        }
    }

    private func addRecipient() {
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else {
            emailValidationMessage = "Enter a valid email address."
            return
        }
        guard !environment.settingsService.emailRecipients.contains(where: {
            $0.caseInsensitiveCompare(email) == .orderedSame
        }) else {
            emailValidationMessage = "This recipient is already listed."
            return
        }

        environment.settingsService.emailRecipients += [email]
        newEmail = ""
        emailValidationMessage = nil
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.displayName)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.textPrimary)
                        Label("Hosted in: \(provider.country)", systemImage: "globe.europe.africa.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if provider.sendsAudioOffDevice {
                            Text("When you transcribe, your audio will be sent to \(provider.displayName) for processing. Review their privacy policy before continuing.")
                        } else {
                            Text("This provider processes audio on your device. No audio leaves your iPhone.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .surfaceCard()

                    Toggle("I allow sending audio to \(provider.displayName)", isOn: $agreed)
                        .tint(AppTheme.accent)
                        .surfaceCard(padding: 14)

                    Button("Confirm") {
                        environment.settingsService.consentProvider(provider)
                        dismiss()
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!agreed && provider.sendsAudioOffDevice)
                }
                .padding(20)
            }
            .background(AppScreenBackground())
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
