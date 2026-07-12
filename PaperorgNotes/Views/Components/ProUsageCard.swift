import SwiftUI

struct ProUsageCard: View {
    let usage: ProUsageInfo
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Included transcription", systemImage: "waveform")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }

            ProgressView(value: usage.usageProgress)
                .tint(usage.usageProgress > 0.85 ? AppTheme.error : AppTheme.accent)

            HStack {
                Text("\(usage.minutesUsedFormatted) used")
                Spacer()
                Text("\(usage.minutesRemainingFormatted) left")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)

            Text("\(usage.minutesLimit) min/month · \(usage.periodDisplayName)")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)

            if let expiry = usage.proExpiryDisplay {
                Text("Renews \(expiry)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension ProUsageInfo {
    var minutesUsedFormatted: String {
        Self.formatMinutes(minutesUsed)
    }

    var minutesRemainingFormatted: String {
        Self.formatMinutes(minutesRemaining)
    }

    static func formatMinutes(_ value: Double) -> String {
        if value >= 10 {
            return "\(Int(value.rounded())) min"
        }
        return String(format: "%.1f min", value)
    }
}
