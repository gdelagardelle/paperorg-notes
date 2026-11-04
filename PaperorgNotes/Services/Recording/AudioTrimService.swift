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
        playableDuration(of: url)
    }

    /// Prefer AVAudioPlayer — it reflects playable audio, not inflated container metadata.
    static func assetDuration(of url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let seconds = duration.seconds
            if seconds.isFinite, seconds > 0 { return seconds }
        }
        return playableDuration(of: url)
    }

    static func fileByteCount(of url: URL) -> Int {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size ?? 0
    }

    static func playableDuration(of url: URL) -> TimeInterval {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        if let player = try? AVAudioPlayer(contentsOf: url),
           player.duration.isFinite,
           player.duration > 0 {
            return player.duration
        }
        // A partial or corrupt recording is not playable. Do not fall back to
        // another duration helper here: the old fallback called this function
        // again and overflowed the stack during launch-time recovery.
        return 0
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

    static func join(urls: [URL], into outputURL: URL) async throws {
        guard urls.count > 1 else { throw AudioTrimError.invalidRange }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioTrimError.exportFailed
        }

        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds > 0 else { throw AudioTrimError.invalidRange }
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw AudioTrimError.exportFailed
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = cursor + duration
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTrimError.exportFailed
        }
        export.outputURL = outputURL
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else {
            throw AudioTrimError.exportFailed
        }
    }
}
