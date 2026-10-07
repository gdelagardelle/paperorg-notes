import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class TeamNameRecorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    func toggleRecording(for person: Teammate, settings: SettingsService) {
        if isRecording {
            stop(for: person, settings: settings)
        } else {
            start(for: person)
        }
    }

    func play(person: Teammate) {
        guard let file = person.nameRecordingFile else { return }
        let url = Self.fileURL(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func start(for person: Teammate) {
        let url = Self.fileURL("\(person.id.uuidString).m4a")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record(forDuration: 4)
        isRecording = recorder?.isRecording == true
    }

    private func stop(for person: Teammate, settings: SettingsService) {
        recorder?.stop()
        isRecording = false
        var updated = person
        updated.nameRecordingFile = "\(person.id.uuidString).m4a"
        settings.replaceTeammate(updated)
        settings.rememberSpokenName(person.trimmedName)
        recorder = nil
    }

    static func fileURL(_ name: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("TeamNames", isDirectory: true).appendingPathComponent(name)
    }
}
