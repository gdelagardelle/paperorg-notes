import PhotosUI
import SwiftUI

struct ExportBrandingSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var logoError: String?
    @State private var previewLogo: UIImage?

    var body: some View {
        @Bindable var settings = environment.settingsService

        Section("PDF Export Branding") {
            SettingsSectionHint(
                text: "Customize Pro PDF exports and email attachments. Upload your logo to replace the Paperorg default."
            )

            TextField("Brand name", text: $settings.exportBrandName)
            TextField("Subtitle (optional)", text: $settings.exportBrandSubtitle)

            HStack(spacing: 12) {
                logoPreview
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $logoPickerItem, matching: .images) {
                        Label(
                            environment.storageService.hasCustomExportLogo ? "Replace logo" : "Upload logo",
                            systemImage: "photo"
                        )
                    }

                    if environment.storageService.hasCustomExportLogo {
                        Button("Use Paperorg logo", role: .destructive) {
                            removeCustomLogo()
                        }
                        .font(.caption)
                    }
                }
            }

            if let logoError {
                Text(logoError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }
        }
        .onAppear {
            refreshPreview()
        }
        .onChange(of: logoPickerItem) { _, item in
            Task { await importLogo(from: item) }
        }
    }

    @ViewBuilder
    private var logoPreview: some View {
        Group {
            if let previewLogo {
                Image(uiImage: previewLogo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 56, height: 56)
        .padding(8)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func refreshPreview() {
        previewLogo = environment.storageService.loadCustomExportLogo()
    }

    private func removeCustomLogo() {
        do {
            try environment.storageService.deleteCustomExportLogo()
            previewLogo = nil
            logoError = nil
        } catch {
            logoError = error.localizedDescription
        }
    }

    private func importLogo(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                logoError = "Could not load the selected image."
                return
            }
            try environment.storageService.saveCustomExportLogo(image)
            refreshPreview()
            logoError = nil
            logoPickerItem = nil
        } catch {
            logoError = error.localizedDescription
        }
    }
}
