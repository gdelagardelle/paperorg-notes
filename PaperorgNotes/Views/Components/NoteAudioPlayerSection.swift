import SwiftUI

struct NoteAudioPlayerSection: View {
    let note: Note
    let audioURL: URL
    @ObservedObject var playback: AudioPlaybackService
    var onTrim: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recording", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text(durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 16) {
                Button {
                    playback.toggleFullPlayback(url: audioURL)
                } label: {
                    Image(systemName: playback.isPlayingFullNote ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { playback.playbackProgress },
                        set: { playback.seekFullPlayback(to: $0) }
                    ),
                    in: 0...1
                )
                .disabled(playback.playbackDuration <= 0)
            }

            HStack {
                Text(elapsedLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if onTrim != nil {
                    Button("Trim", action: { onTrim?() })
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .surfaceCard()
        .onAppear {
            playback.prepareFullPlayback(url: audioURL)
        }
        .onDisappear {
            playback.stopFullPlayback()
        }
    }

    private var durationLabel: String {
        DurationFormatter.format(playback.playbackDuration > 0 ? playback.playbackDuration : note.durationSeconds)
    }

    private var elapsedLabel: String {
        let elapsed = playback.playbackDuration * playback.playbackProgress
        return "\(DurationFormatter.format(elapsed)) / \(durationLabel)"
    }
}

struct AudioTrimSheet: View {
    let audioURL: URL
    let onSave: (TimeInterval, TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var totalDuration: TimeInterval = 0
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let minClipLength: TimeInterval = 0.5

    private var canTrim: Bool { totalDuration >= minClipLength }

    private var maxTrimStart: TimeInterval {
        max(0, trimEnd - minClipLength)
    }

    private var minTrimEnd: TimeInterval {
        min(totalDuration, trimStart + minClipLength)
    }

    private var trimStartRange: ClosedRange<Double> {
        let upper = max(maxTrimStart, 0)
        return 0...upper
    }

    private var trimEndRange: ClosedRange<Double> {
        let lower = min(minTrimEnd, totalDuration)
        let upper = max(totalDuration, lower)
        return lower...upper
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Drag the handles to keep only the part you want. Transcription will use the trimmed audio if you reprocess.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if canTrim {
                    Section("Keep from") {
                        Slider(value: trimStartBinding, in: trimStartRange, step: 0.1)
                        Text(DurationFormatter.format(trimStart))
                            .font(.caption.monospacedDigit())
                    }

                    Section("Keep until") {
                        Slider(value: trimEndBinding, in: trimEndRange, step: 0.1)
                        Text(DurationFormatter.format(trimEnd))
                            .font(.caption.monospacedDigit())
                    }

                    Section {
                        Text("New length: \(DurationFormatter.format(trimEnd - trimStart))")
                            .font(.subheadline.weight(.semibold))
                    }
                } else if totalDuration > 0 {
                    Section {
                        Text("This recording is too short to trim.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } else {
                    Section {
                        Text("Could not read the recording duration.")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppTheme.error)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Trim Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTrim() }
                        .disabled(isSaving || !canTrim)
                }
            }
            .onAppear {
                AudioFileReader.prepareForReading(audioURL)
                let playable = AudioTrimService.playableDuration(of: audioURL)
                totalDuration = playable > 0 ? playable : AudioTrimService.duration(of: audioURL)
                trimStart = 0
                trimEnd = totalDuration
                clampTrimValues()
            }
        }
    }

    private var trimStartBinding: Binding<Double> {
        Binding(
            get: { trimStart },
            set: { newValue in
                trimStart = min(max(newValue, trimStartRange.lowerBound), trimStartRange.upperBound)
                clampTrimValues()
            }
        )
    }

    private var trimEndBinding: Binding<Double> {
        Binding(
            get: { trimEnd },
            set: { newValue in
                trimEnd = min(max(newValue, trimEndRange.lowerBound), trimEndRange.upperBound)
                clampTrimValues()
            }
        )
    }

    private func clampTrimValues() {
        guard totalDuration > 0 else {
            trimStart = 0
            trimEnd = 0
            return
        }

        trimEnd = min(max(trimEnd, minClipLength), totalDuration)
        trimStart = min(max(trimStart, 0), max(0, trimEnd - minClipLength))

        if trimEnd - trimStart < minClipLength {
            trimEnd = min(totalDuration, trimStart + minClipLength)
            trimStart = max(0, trimEnd - minClipLength)
        }
    }

    private func saveTrim() {
        guard canTrim, trimEnd > trimStart else {
            errorMessage = AudioTrimError.invalidRange.localizedDescription
            return
        }
        isSaving = true
        errorMessage = nil
        onSave(trimStart, trimEnd)
        dismiss()
    }
}
