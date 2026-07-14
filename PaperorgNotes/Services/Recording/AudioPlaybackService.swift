import SwiftUI
import AVFoundation

@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSegmentId: UUID?
    @Published private(set) var isPlayingFullNote = false
    @Published private(set) var playbackProgress: Double = 0
    @Published private(set) var playbackDuration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func prepareFullPlayback(url: URL) {
        guard playbackDuration == 0 else { return }
        do {
            AudioFileReader.prepareForReading(url)
            let preview = try AVAudioPlayer(contentsOf: url)
            playbackDuration = preview.duration
        } catch {
            playbackDuration = 0
        }
    }

    func toggleFullPlayback(url: URL) {
        if isPlayingFullNote {
            stopFullPlayback()
        } else {
            playFull(url: url)
        }
    }

    func playFull(url: URL) {
        stop()
        do {
            AudioFileReader.prepareForReading(url)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: url)
            playbackDuration = player?.duration ?? 0
            player?.play()
            isPlayingFullNote = true
            isPlaying = true
            startProgressTimer()
        } catch {
            stopFullPlayback()
        }
    }

    func seekFullPlayback(to progress: Double) {
        guard let player, playbackDuration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        player.currentTime = playbackDuration * clamped
        playbackProgress = clamped
        if !player.isPlaying, isPlayingFullNote {
            player.play()
        }
    }

    func stopFullPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlayingFullNote = false
        isPlaying = false
        playbackProgress = 0
        playbackDuration = 0
    }

    func play(url: URL, segment: TranscriptSegmentModel) {
        stopFullPlayback()
        do {
            AudioFileReader.prepareForReading(url)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: url)
            player?.currentTime = segment.startTime
            player?.play()
            isPlaying = true
            currentSegmentId = segment.id

            let duration = segment.endTime - segment.startTime
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(duration, 0.5) * 1_000_000_000))
                await MainActor.run {
                    if self.currentSegmentId == segment.id {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        isPlayingFullNote = false
        currentSegmentId = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, self.playbackDuration > 0 else { return }
                self.playbackProgress = player.currentTime / self.playbackDuration
                if !player.isPlaying {
                    self.stopFullPlayback()
                }
            }
        }
    }
}
