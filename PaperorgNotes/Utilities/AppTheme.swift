import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppTheme {
    static let navy = Color(red: 0.078, green: 0.137, blue: 0.239)
    static let orange = Color(red: 0.961, green: 0.416, blue: 0.039)

    static let primary = adaptive(
        light: (0.078, 0.137, 0.239),
        dark: (0.961, 0.969, 0.984)
    )
    static let accent = orange
    static let background = adaptive(
        light: (0.961, 0.969, 0.984),
        dark: (0.043, 0.071, 0.125)
    )
    static let surface = adaptive(
        light: (1, 1, 1),
        dark: (0.086, 0.125, 0.200)
    )
    static let surfaceElevated = surface
    static let border = adaptive(
        light: (0.878, 0.898, 0.925),
        dark: (0.173, 0.227, 0.318)
    )
    static let accentSoft = accent.opacity(0.14)
    static let primarySoft = adaptive(
        light: (0.078, 0.137, 0.239, 0.10),
        dark: (1, 1, 1, 0.12)
    )
    static let heroGradientBottom = adaptive(
        light: (0.949, 0.965, 0.988),
        dark: (0.043, 0.071, 0.125)
    )
    static let textPrimary = primary
    static let textSecondary = adaptive(
        light: (0.302, 0.376, 0.482),
        dark: (0.604, 0.659, 0.737)
    )
    static let warning = accent
    static let error = adaptive(
        light: (0.84, 0.27, 0.27),
        dark: (1.0, 0.541, 0.502)
    )
    static let unclearHighlight = adaptive(
        light: (1.0, 0.949, 0.898),
        dark: (0.22, 0.14, 0.08)
    )
    static let recordRed = accent
    static let filledPrimary = adaptive(
        light: (0.078, 0.137, 0.239),
        dark: (0.961, 0.416, 0.039)
    )
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

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        adaptive(light: (light.0, light.1, light.2, 1), dark: (dark.0, dark.1, dark.2, 1))
    }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: rgb.3)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: rgb.3)
        })
        #endif
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
