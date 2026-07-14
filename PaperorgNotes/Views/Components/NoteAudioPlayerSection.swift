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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Drag the handles to keep only the part you want. Transcription will use the trimmed audio if you reprocess.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if totalDuration > 0 {
                    Section("Keep from") {
                        Slider(value: $trimStart, in: 0...max(trimEnd - 0.5, 0.5), step: 0.1)
                        Text(DurationFormatter.format(trimStart))
                            .font(.caption.monospacedDigit())
                    }

                    Section("Keep until") {
                        Slider(value: $trimEnd, in: min(trimStart + 0.5, totalDuration)...totalDuration, step: 0.1)
                        Text(DurationFormatter.format(trimEnd))
                            .font(.caption.monospacedDigit())
                    }

                    Section {
                        Text("New length: \(DurationFormatter.format(trimEnd - trimStart))")
                            .font(.subheadline.weight(.semibold))
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
                        .disabled(isSaving || totalDuration <= 0)
                }
            }
            .onAppear {
                totalDuration = AudioTrimService.duration(of: audioURL)
                trimEnd = totalDuration
            }
        }
    }

    private func saveTrim() {
        isSaving = true
        errorMessage = nil
        onSave(trimStart, trimEnd)
        dismiss()
    }
}
