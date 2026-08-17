import AVFoundation
import Foundation

struct PreparedTranscriptionAudio {
    let data: Data
    let fileName: String
    let mimeType: String
    let gainAppliedDecibels: Float
}

enum AudioFileReader {
    private static let quietPeakThreshold: Float = -30
    private static let targetPeak: Float = -6
    private static let maximumGain: Float = 30

    /// Reads recorded audio, relaxing overly strict file protection when needed.
    static func readData(from url: URL) throws -> Data {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        prepareForReading(url)
        
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TranscriptionError.providerError(
                "Could not read audio file: \(error.localizedDescription)"
            )
        }
    }
    
    static func prepareForReading(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    /// Creates a temporary, leveled WAV payload only when the source peak is
    /// abnormally quiet. The original recording is never modified.
    static func prepareForTranscription(from url: URL) throws -> PreparedTranscriptionAudio? {
        prepareForReading(url)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            return nil
        }

        guard audioFile.length > 0,
              audioFile.length <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
              ) else {
            return nil
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return nil
        }

        guard buffer.frameLength > 0,
              let channels = buffer.floatChannelData else {
            return nil
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                peak = max(peak, abs(channels[channel][frame]))
            }
        }

        guard peak > 0 else { return nil }
        let peakDecibels = 20 * log10(peak)
        guard peakDecibels < quietPeakThreshold else { return nil }

        let gainDecibels = min(maximumGain, targetPeak - peakDecibels)
        let linearGain = pow(10, gainDecibels / 20)
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                channels[channel][frame] = max(
                    -1,
                    min(1, channels[channel][frame] * linearGain)
                )
            }
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("paperorg-transcription-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            let output = try AVAudioFile(
                forWriting: temporaryURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try output.write(from: buffer)
        }

        return PreparedTranscriptionAudio(
            data: try Data(contentsOf: temporaryURL),
            fileName: "leveled-\(url.deletingPathExtension().lastPathComponent).wav",
            mimeType: "audio/wav",
            gainAppliedDecibels: gainDecibels
        )
    }
}
