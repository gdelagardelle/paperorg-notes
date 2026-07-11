import SwiftUI

enum AppTheme {
    // Paperorg Notes brand colors, matched to the app icon.
    static let primary = Color(red: 0.078, green: 0.137, blue: 0.239)
    static let accent = Color(red: 0.961, green: 0.416, blue: 0.039)
    static let background = Color(red: 0.961, green: 0.969, blue: 0.984)
    static let surface = Color.white
    static let surfaceElevated = Color.white
    static let border = Color(red: 0.878, green: 0.898, blue: 0.925)
    static let accentSoft = accent.opacity(0.14)
    static let primarySoft = primary.opacity(0.10)
    static let heroGradientBottom = Color(red: 0.949, green: 0.965, blue: 0.988)
    static let textPrimary = primary
    static let textSecondary = Color(red: 0.302, green: 0.376, blue: 0.482)
    static let warning = accent
    static let error = Color(red: 0.84, green: 0.27, blue: 0.27)
    static let unclearHighlight = Color(red: 1.0, green: 0.949, blue: 0.898)
    static let recordRed = accent
    
    static let speakerColors: [Color] = [
        primary,
        Color(red: 0.161, green: 0.459, blue: 0.729),
        accent,
        Color(red: 0.718, green: 0.267, blue: 0.118)
    ]
    
    static func speakerColor(for label: String?) -> Color {
        speakerColors[SpeakerLabelFormatter.colorIndex(for: label) % speakerColors.count]
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: AppTheme.primary.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.primary.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DurationFormatter {
    static func format(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
