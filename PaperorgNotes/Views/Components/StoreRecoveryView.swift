import SwiftUI

struct StoreRecoveryView: View {
    let error: Error
    @State private var didReset = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.warning)

            Text("Unable to Open Notes")
                .font(.title2.bold())

            Text(
                didReset
                    ? "The local database was reset. Please force quit and reopen Paperorg Notes."
                    : "Paperorg Notes could not open its saved notes. You can reset local storage and start fresh."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(AppTheme.textSecondary)

            if !didReset {
                Button("Reset Local Database") {
                    resetStore()
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    private func resetStore() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperorgNotes", isDirectory: true)
        try? FileManager.default.removeItem(at: supportURL)
        didReset = true
    }
}
