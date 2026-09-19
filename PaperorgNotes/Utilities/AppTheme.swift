import SwiftUI
import UIKit

enum AppTheme {
    // Paperorg Notes brand colors, matched to the app icon.
    static let navy = Color(red: 0.078, green: 0.137, blue: 0.239)
    static let orange = Color(red: 0.961, green: 0.416, blue: 0.039)

    /// Body text and icons. Navy in light, mist in dark.
    static let primary = adaptive(light: UIColor(red: 0.078, green: 0.137, blue: 0.239, alpha: 1), dark: UIColor(red: 0.961, green: 0.969, blue: 0.984, alpha: 1))
    static let accent = orange
    static let background = adaptive(light: UIColor(red: 0.961, green: 0.969, blue: 0.984, alpha: 1), dark: UIColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1))
    static let surface = adaptive(light: .white, dark: UIColor(red: 0.086, green: 0.125, blue: 0.200, alpha: 1))
    static let surfaceElevated = surface
    static let border = adaptive(light: UIColor(red: 0.878, green: 0.898, blue: 0.925, alpha: 1), dark: UIColor(red: 0.173, green: 0.227, blue: 0.318, alpha: 1))
    static let accentSoft = accent.opacity(0.14)
    static let primarySoft = adaptive(light: UIColor(red: 0.078, green: 0.137, blue: 0.239, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
    static let heroGradientBottom = adaptive(light: UIColor(red: 0.949, green: 0.965, blue: 0.988, alpha: 1), dark: UIColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1))
    static let textPrimary = primary
    static let textSecondary = adaptive(light: UIColor(red: 0.302, green: 0.376, blue: 0.482, alpha: 1), dark: UIColor(red: 0.604, green: 0.659, blue: 0.737, alpha: 1))
    static let warning = accent
    static let error = adaptive(light: UIColor(red: 0.84, green: 0.27, blue: 0.27, alpha: 1), dark: UIColor(red: 1.0, green: 0.541, blue: 0.502, alpha: 1))
    static let unclearHighlight = adaptive(light: UIColor(red: 1.0, green: 0.949, blue: 0.898, alpha: 1), dark: UIColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 1))
    static let recordRed = accent
    /// Filled primary buttons: navy on light, orange on dark so the fill stays distinct from the page.
    static let filledPrimary = adaptive(light: UIColor(red: 0.078, green: 0.137, blue: 0.239, alpha: 1), dark: UIColor(red: 0.961, green: 0.416, blue: 0.039, alpha: 1))
    static let onFilled = Color.white

    static let speakerColors: [Color] = [
        navy,
        Color(red: 0.161, green: 0.459, blue: 0.729),
        accent,
        Color(red: 0.718, green: 0.267, blue: 0.118)
    ]

    static func speakerColor(for label: String?) -> Color {
        speakerColors[SpeakerLabelFormatter.colorIndex(for: label) % speakerColors.count]
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
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
            .shadow(color: AppTheme.navy.opacity(0.05), radius: 10, y: 4)
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
            .foregroundStyle(AppTheme.onFilled)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.filledPrimary.opacity(configuration.isPressed ? 0.8 : 1))
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
