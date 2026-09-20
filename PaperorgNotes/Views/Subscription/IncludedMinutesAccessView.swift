import SwiftUI

struct IncludedMinutesAccessView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var message: String?
    @State private var requestUpgrade = false
    var onUpgrade: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)

                Text(L10n.Included.title)
                    .font(.title2.bold())
                Text(L10n.Included.detail)
                    .foregroundStyle(AppTheme.textSecondary)

                Button(L10n.Included.start) {
                    activateIncludedMinutes()
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(isWorking)

                Button(L10n.Included.upgrade) {
                    requestUpgrade = true
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                if isWorking {
                    ProgressView(L10n.Included.connecting)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(L10n.Included.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
            .onDisappear {
                if requestUpgrade {
                    onUpgrade?()
                }
            }
        }
    }

    private func friendlyRegistrationError(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return L10n.Included.offline
            default:
                break
            }
        }
        if let backend = error as? ProBackendError {
            return backend.localizedDescription
        }
        return L10n.Included.connectionFailed
    }

    private func activateIncludedMinutes() {
        isWorking = true
        message = nil
        Task {
            do {
                let usage = try await environment.proBackendClient.register()
                if usage.minutesLimit > 0 {
                    dismiss()
                } else {
                    message = L10n.Included.unavailable
                }
            } catch {
                message = friendlyRegistrationError(for: error)
            }
            isWorking = false
        }
    }
}
