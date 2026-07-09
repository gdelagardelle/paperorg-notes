import SwiftUI
import AVFoundation

@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSegmentId: UUID?
    
    private var player: AVAudioPlayer?
    
    func play(url: URL, segment: TranscriptSegmentModel) {
        stop()
        do {
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
        player?.stop()
        player = nil
        isPlaying = false
        currentSegmentId = nil
    }
}
