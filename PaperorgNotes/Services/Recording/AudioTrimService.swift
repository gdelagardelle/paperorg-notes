import AVFoundation
import Foundation

enum AudioTrimError: LocalizedError {
    case invalidRange
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "Choose a valid trim range inside the recording."
        case .exportFailed:
            return "Could not save the trimmed audio."
        }
    }
}

enum AudioTrimService {
    static func duration(of url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    /// Prefer AVAudioPlayer — it reflects playable audio, not inflated container metadata.
    static func playableDuration(of url: URL) -> TimeInterval {
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           !data.isEmpty,
           let player = try? AVAudioPlayer(data: data),
           player.duration.isFinite,
           player.duration > 0 {
            return player.duration
        }
        return duration(of: url)
    }

    static func trim(sourceURL: URL, start: TimeInterval, end: TimeInterval) async throws -> URL {
        guard end > start, start >= 0 else { throw AudioTrimError.invalidRange }

        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = playableDuration(of: sourceURL)
        guard assetDuration > 0, end <= assetDuration + 0.05 else { throw AudioTrimError.invalidRange }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTrimError.exportFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        export.outputURL = outputURL
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )

        await export.export()

        guard export.status == .completed else {
            throw AudioTrimError.exportFailed
        }
        return outputURL
    }
}
