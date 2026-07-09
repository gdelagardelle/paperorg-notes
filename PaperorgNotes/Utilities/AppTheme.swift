import SwiftUI

enum AppTheme {
    static let primary = Color(red: 0.10, green: 0.42, blue: 0.42)
    static let background = Color(red: 0.98, green: 0.97, blue: 0.96)
    static let surface = Color.white
    static let textPrimary = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let textSecondary = Color(red: 0.42, green: 0.42, blue: 0.43)
    static let warning = Color(red: 0.91, green: 0.66, blue: 0.22)
    static let error = Color(red: 0.84, green: 0.27, blue: 0.27)
    static let unclearHighlight = Color(red: 1.0, green: 0.95, blue: 0.80)
    static let recordRed = Color(red: 0.90, green: 0.22, blue: 0.27)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
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
