import SwiftUI

// MARK: - Layout primitives

struct AppScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.background, AppTheme.heroGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct SurfaceCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: AppTheme.primary.opacity(0.06), radius: 16, y: 6)
    }
}

extension View {
    func surfaceCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(SurfaceCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppBrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Paperorg Notes")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Capture, transcribe, send")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Chips & badges

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct SelectionChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? AppTheme.primary : AppTheme.surfaceElevated)
            .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? AppTheme.primary : AppTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NoteStatusBadge: View {
    let status: NoteStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            icon
            if !compact {
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 4)
        .foregroundStyle(color)
        .background(compact ? Color.clear : color.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
        case .processing:
            ProgressView()
                .scaleEffect(0.65)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
        case .draft:
            Image(systemName: "circle.dashed")
        }
    }

    private var label: String {
        switch status {
        case .ready: return "Ready"
        case .processing: return "Processing"
        case .failed: return "Failed"
        case .draft: return "Draft"
        }
    }

    private var color: Color {
        switch status {
        case .ready: return AppTheme.primary
        case .processing: return AppTheme.accent
        case .failed: return AppTheme.error
        case .draft: return AppTheme.textSecondary
        }
    }
}

// MARK: - Note cards

struct NoteCardRow: View {
    let note: Note
    var style: Style = .standard

    enum Style {
        case standard
        case compact
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentStripe)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: style == .compact ? 4 : 6) {
                HStack(spacing: 8) {
                    Text(note.title)
                        .font(style == .compact ? .subheadline.bold() : .headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                    }

                    Spacer(minLength: 0)

                    NoteStatusBadge(status: note.noteStatus, compact: style == .compact)
                }

                HStack(spacing: 8) {
                    Text(note.appLanguage.flag)
                    Text("·")
                    Text(formattedDate)
                    Text("·")
                    Text(DurationFormatter.format(note.durationSeconds))
                    if let project = note.projectName, !project.isEmpty {
                        Text("·")
                        Text(project)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

                if style == .standard, !note.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.primarySoft)
                                .foregroundStyle(AppTheme.primary)
                                .clipShape(Capsule())
                        }
                    }
                }

                if style == .standard,
                   let summary = note.summaryShort,
                   !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if style == .compact {
                    Text(note.noteOutputType.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .surfaceCard(padding: style == .compact ? 14 : 16)
    }

    private var accentStripe: Color {
        switch note.noteStatus {
        case .ready: return AppTheme.primary
        case .processing: return AppTheme.accent
        case .failed: return AppTheme.error
        case .draft: return AppTheme.border
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: note.createdAt)
    }
}

// MARK: - Recording UI

struct ScrollingAudioWaveform: View {
    let level: Float
    let isActive: Bool
    var isVisible: Bool = true

    @State private var samples: [CGFloat] = []
    @State private var phase: CGFloat = 0

    private let maxSamples = 130

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04, paused: !isActive)) { timeline in
            GeometryReader { geo in
                ZStack {
                    waveform(in: geo.size, closePath: true)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.03),
                                    AppTheme.accent.opacity(0.14),
                                    AppTheme.accent.opacity(0.22)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    waveform(in: geo.size, closePath: false)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.2),
                                    AppTheme.accent.opacity(0.75),
                                    AppTheme.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            .onChange(of: timeline.date) { _, _ in
                guard isActive else { return }
                appendSample(from: level)
            }
        }
        .frame(height: 58)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .opacity(isVisible ? 1 : 0.18)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onChange(of: isActive) { _, active in
            if active {
                if samples.isEmpty {
                    samples = Array(repeating: 0.06, count: maxSamples)
                }
            } else if !isVisible {
                samples = []
                phase = 0
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible, samples.isEmpty {
                samples = Array(repeating: 0.06, count: maxSamples)
            } else if !visible {
                samples = []
                phase = 0
            }
        }
    }

    private func appendSample(from level: Float) {
        phase += 0.18 + CGFloat(level) * 1.05
        let harmonic = sin(phase) * 0.34
            + sin(phase * 2.4) * 0.2
            + sin(phase * 0.62) * 0.14
        let envelope = CGFloat(level) * 0.95 + 0.05
        let value = min(1, max(0.04, envelope * (0.56 + harmonic)))
        samples.append(value)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func waveform(in size: CGSize, closePath: Bool) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }

        let midY = size.height * 0.5
        let amplitude = size.height * 0.44
        let step = size.width / CGFloat(samples.count - 1)

        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * step
            let y = midY - (sample - 0.5) * 2 * amplitude
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                let previousX = CGFloat(index - 1) * step
                let previousY = midY - (samples[index - 1] - 0.5) * 2 * amplitude
                let controlX = (previousX + x) * 0.5
                path.addQuadCurve(
                    to: CGPoint(x: x, y: y),
                    control: CGPoint(x: controlX, y: previousY)
                )
            }
        }

        if closePath {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }

        return path
    }
}

struct RecordHeroStack: View {
    let state: RecordingState
    let pulseAnimation: Bool
    let audioLevel: Float
    let action: () -> Void

    var body: some View {
        ZStack {
            ScrollingAudioWaveform(
                level: audioLevel,
                isActive: state == .recording,
                isVisible: state == .recording || state == .paused
            )
            .padding(.horizontal, -8)
            .allowsHitTesting(false)

            RecordHeroButton(
                state: state,
                pulseAnimation: pulseAnimation,
                audioLevel: audioLevel,
                action: action
            )
        }
        .frame(height: 168)
    }
}

struct AudioLevelMeter: View {
    let level: Float
    let isActive: Bool
    private let barCount = 7

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor(for: index))
                    .frame(width: 5, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(height: 28)
        .opacity(isActive ? 1 : 0.35)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index + 1) / Float(barCount + 1)
        let active = isActive && level >= threshold * 0.55
        let base: CGFloat = 8
        let peak: CGFloat = 8 + CGFloat(index + 1) * 2.2
        return active ? peak : base
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / Float(barCount + 1)
        return isActive && level >= threshold * 0.55 ? AppTheme.accent : AppTheme.border
    }
}

struct RecordControlButton: View {
    let title: String
    let systemImage: String
    var role: Role = .secondary

    enum Role {
        case secondary
        case destructive
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(border, lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch role {
        case .secondary: return AppTheme.primary
        case .destructive: return AppTheme.error
        }
    }

    private var background: Color {
        switch role {
        case .secondary: return AppTheme.primarySoft
        case .destructive: return AppTheme.error.opacity(0.10)
        }
    }

    private var border: Color {
        switch role {
        case .secondary: return AppTheme.border
        case .destructive: return AppTheme.error.opacity(0.25)
        }
    }
}

struct RecordHeroButton: View {
    let state: RecordingState
    let pulseAnimation: Bool
    let audioLevel: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(AppTheme.accent.opacity(0.18), lineWidth: 10)
                    .frame(width: 156, height: 156)
                    .scaleEffect(pulseScale)
                    .animation(pulseAnimation ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: pulseAnimation)

                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 132, height: 132)
                    .scaleEffect(1 + CGFloat(audioLevel) * 0.08)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 16, y: 8)

                Image(systemName: iconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .idle: return "mic.fill"
        case .recording, .paused: return "stop.fill"
        }
    }

    private var pulseScale: CGFloat {
        state == .recording ? 1.06 : 1.0
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Start recording"
        case .recording, .paused: return "Stop recording"
        }
    }
}

// MARK: - Recording banner

struct RecordingInProgressBanner: View {
    let state: RecordingState
    let duration: TimeInterval
    let onOpenRecordTab: () -> Void

    var body: some View {
        Button(action: onOpenRecordTab) {
            HStack(spacing: 10) {
                Image(systemName: state == .paused ? "pause.circle.fill" : "record.circle")
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state == .paused ? "Recording paused" : "Recording in progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Tap to return to Record and tap Stop when finished")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text(DurationFormatter.format(duration))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button styles

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.primarySoft.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

// MARK: - Settings & forms

struct SettingsScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppScreenBackground())
            .tint(AppTheme.accent)
    }
}

extension View {
    func settingsScreenStyle() -> some View {
        modifier(SettingsScreenStyle())
    }
}

struct SettingsSectionHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetaPill: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.primarySoft)
        .foregroundStyle(AppTheme.primary)
        .clipShape(Capsule())
    }
}
