import AVFoundation
import Foundation
import Observation
import UIKit

enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case paused
}

@Observable
@MainActor
final class RecordingService: NSObject {
    private(set) var state: RecordingState = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var audioLevel: Float = 0
    private(set) var qualityWarning: String?
    private(set) var currentNoteId: UUID?
    private(set) var sessionId: UUID = UUID()
    
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var tempURL: URL?
    private let storage: StorageService
    private var lowLevelStart: Date?
    
    init(storage: StorageService) {
        self.storage = storage
        super.init()
        observeAppLifecycle()
    }
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func start(noteId: UUID) async throws {
        guard state == .idle else { throw RecordingError.alreadyRecording }
        
        let granted = await requestPermission()
        guard granted else { throw RecordingError.permissionDenied }
        
        try configureAudioSession()
        
        sessionId = UUID()
        currentNoteId = noteId
        tempURL = storage.recordingsDirectory.appendingPathComponent("temp-\(sessionId.uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        guard let url = tempURL else { throw RecordingError.setupFailed("Invalid temp URL") }
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            state = .recording
            duration = 0
            startTimer()
            persistCheckpoint()
        } catch {
            throw RecordingError.setupFailed(error.localizedDescription)
        }
    }
    
    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
        timer?.invalidate()
        persistCheckpoint()
    }
    
    func resume() {
        guard state == .paused else { return }
        recorder?.record()
        state = .recording
        startTimer()
    }
    
    func stop() async throws -> (noteId: UUID, audioURL: URL, duration: TimeInterval) {
        guard let noteId = currentNoteId, let temp = tempURL else {
            throw RecordingError.notRecording
        }
        
        recorder?.stop()
        timer?.invalidate()
        timer = nil

        syncDurationFromTempFile()
        let finalDuration = duration
        let finalURL = try storage.finalizeRecording(from: temp, noteId: noteId)
        storage.deleteCheckpoint(sessionId: sessionId)
        
        resetState()
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        return (noteId, finalURL, finalDuration)
    }
    
    func cancel() {
        recorder?.stop()
        timer?.invalidate()
        if let temp = tempURL { try? FileManager.default.removeItem(at: temp) }
        storage.deleteCheckpoint(sessionId: sessionId)
        resetState()
    }

    /// Finalizes recordings left behind by an interrupted app session.
    /// Callers can use the returned note IDs to reconcile the corresponding SwiftData notes.
    func recoverInterruptedRecordings() -> [RecoveredRecording] {
        storage.loadPendingCheckpoints().compactMap { recover(checkpoint: $0) }
    }

    /// Attempts to locate or finalize audio for a specific note (checkpoint temp file or saved m4a).
    func recoverRecording(for noteId: UUID) -> RecoveredRecording? {
        if let existing = existingRecording(for: noteId) {
            return existing
        }
        guard let checkpoint = storage.loadPendingCheckpoints().first(where: { $0.noteId == noteId }) else {
            return nil
        }
        return recover(checkpoint: checkpoint)
    }

    func existingRecording(for noteId: UUID) -> RecoveredRecording? {
        let audioURL = storage.audioURL(for: noteId)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return nil }
        let measuredDuration = AudioTrimService.duration(of: audioURL)
        guard measuredDuration > 0 else { return nil }
        return RecoveredRecording(noteId: noteId, audioURL: audioURL, duration: measuredDuration)
    }

    private func recover(checkpoint: RecordingCheckpoint) -> RecoveredRecording? {
        let temporaryURL = URL(fileURLWithPath: checkpoint.tempAudioPath)
        let expectedPrefix = storage.recordingsDirectory.path + "/temp-"
        guard temporaryURL.path.hasPrefix(expectedPrefix),
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            storage.deleteCheckpoint(sessionId: checkpoint.sessionId)
            return nil
        }

        do {
            let audioURL = try storage.finalizeRecording(from: temporaryURL, noteId: checkpoint.noteId)
            storage.deleteCheckpoint(sessionId: checkpoint.sessionId)
            let measuredDuration = AudioTrimService.duration(of: audioURL)
            let duration = max(checkpoint.duration, measuredDuration)
            return RecoveredRecording(
                noteId: checkpoint.noteId,
                audioURL: audioURL,
                duration: duration
            )
        } catch {
            return nil
        }
    }
    
    private func resetState() {
        state = .idle
        duration = 0
        audioLevel = 0
        qualityWarning = nil
        currentNoteId = nil
        recorder = nil
        tempURL = nil
        lowLevelStart = nil
    }
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        duration += 0.1
        recorder?.updateMeters()
        let level = recorder?.averagePower(forChannel: 0) ?? -160
        audioLevel = normalizedLevel(level)
        evaluateQuality(level: level)
        
        if Int(duration * 10) % 50 == 0 {
            persistCheckpoint()
        }
    }
    
    private func normalizedLevel(_ db: Float) -> Float {
        max(0, min(1, (db + 60) / 60))
    }
    
    private func evaluateQuality(level: Float) {
        if level < -50 {
            if lowLevelStart == nil { lowLevelStart = .now }
            if let start = lowLevelStart, Date.now.timeIntervalSince(start) > 3 {
                qualityWarning = "Low microphone input — move closer or check mic"
            }
        } else {
            lowLevelStart = nil
            qualityWarning = nil
        }
    }
    
    private func persistCheckpoint() {
        guard let noteId = currentNoteId, let temp = tempURL else { return }
        syncDurationFromTempFile()
        try? storage.saveCheckpoint(
            sessionId: sessionId,
            noteId: noteId,
            tempAudioPath: temp.path,
            duration: duration
        )
    }

    /// UI timers pause when the device sleeps; read the growing m4a on disk for the real length.
    private func syncDurationFromTempFile() {
        guard let temp = tempURL, FileManager.default.fileExists(atPath: temp.path) else { return }
        let measured = AudioTrimService.duration(of: temp)
        if measured > duration {
            duration = measured
        }
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBackgrounding()
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBackgrounding()
            }
        }
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppForegrounding()
            }
        }
    }

    private func handleAppBackgrounding() {
        guard state != .idle else { return }
        syncDurationFromTempFile()
        persistCheckpoint()
    }

    private func handleAppForegrounding() {
        guard state != .idle else { return }
        syncDurationFromTempFile()
        if state == .recording, recorder?.isRecording == false {
            state = .paused
            timer?.invalidate()
            qualityWarning = "Recording was paused while the phone was locked. Tap Resume or Stop."
        }
    }
}

struct RecoveredRecording: Sendable, Equatable {
    let noteId: UUID
    let audioURL: URL
    let duration: TimeInterval
}

extension RecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            qualityWarning = "Recording error — saving checkpoint"
            persistCheckpoint()
        }
    }
}
