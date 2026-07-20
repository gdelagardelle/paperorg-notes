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
    private var isStoppingIntentionally = false
    private var recorderHasFinished = false
    private var stopFinishContinuation: CheckedContinuation<Void, Never>?

    private static let recorderSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

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
        recorderHasFinished = false
        tempURL = storage.recordingsDirectory.appendingPathComponent("temp-\(sessionId.uuidString).m4a")

        guard let url = tempURL else { throw RecordingError.setupFailed("Invalid temp URL") }

        do {
            recorder = try AVAudioRecorder(url: url, settings: Self.recorderSettings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            guard recorder?.prepareToRecord() == true else {
                throw RecordingError.setupFailed("Could not prepare the recorder.")
            }
            guard recorder?.record() == true else {
                throw RecordingError.setupFailed("Could not start recording.")
            }
            state = .recording
            duration = 0
            qualityWarning = nil
            startTimer()
            persistCheckpoint()
            persistActiveSession()
        } catch {
            recorder = nil
            tempURL = nil
            currentNoteId = nil
            throw RecordingError.setupFailed(error.localizedDescription)
        }
    }

    func pause() {
        guard state == .recording, !recorderHasFinished else { return }
        recorder?.pause()
        state = .paused
        timer?.invalidate()
        syncDurationFromRecorder()
        persistCheckpoint()
    }

    func resume() {
        guard state == .paused else { return }
        guard !recorderHasFinished else {
            qualityWarning = "Recording already ended. Tap Stop to save."
            return
        }

        do {
            try configureAudioSession()
        } catch {
            qualityWarning = "Could not restore the audio session. Tap Stop to save."
            return
        }

        guard recorder?.record() == true else {
            recorderHasFinished = true
            qualityWarning = "Could not resume recording. Tap Stop to save what was captured."
            return
        }

        state = .recording
        qualityWarning = nil
        startTimer()
    }

    func stop() async throws -> (noteId: UUID, audioURL: URL, duration: TimeInterval) {
        guard let noteId = currentNoteId, let temp = tempURL else {
            throw RecordingError.notRecording
        }

        isStoppingIntentionally = true
        timer?.invalidate()
        timer = nil

        if recorder?.isRecording == true {
            await withCheckedContinuation { continuation in
                stopFinishContinuation = continuation
                recorder?.stop()
            }
        } else {
            recorder?.stop()
        }

        isStoppingIntentionally = false
        stopFinishContinuation = nil

        syncDurationFromRecorder()

        let finalURL = try storage.finalizeRecording(from: temp, noteId: noteId)
        storage.deleteCheckpoint(sessionId: sessionId)
        clearActiveSession()

        let playableDuration = AudioTrimService.playableDuration(of: finalURL)
        let finalDuration = playableDuration > 0 ? playableDuration : duration

        resetState()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return (noteId, finalURL, finalDuration)
    }

    func cancel() {
        isStoppingIntentionally = true
        recorder?.stop()
        timer?.invalidate()
        if let temp = tempURL { try? FileManager.default.removeItem(at: temp) }
        storage.deleteCheckpoint(sessionId: sessionId)
        clearActiveSession()
        isStoppingIntentionally = false
        stopFinishContinuation = nil
        resetState()
    }

    /// Finalizes recordings left behind by an interrupted app session.
    func recoverInterruptedRecordings(excludingSessionId activeSessionId: UUID? = nil) -> [RecoveredRecording] {
        storage.loadPendingCheckpoints().compactMap { checkpoint in
            if checkpoint.sessionId == activeSessionId { return nil }
            if state != .idle,
               checkpoint.sessionId == sessionId || checkpoint.noteId == currentNoteId {
                return nil
            }
            return recover(checkpoint: checkpoint)
        }
    }

    func recoverRecording(for noteId: UUID) -> RecoveredRecording? {
        if state != .idle, noteId == currentNoteId { return nil }
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
        let measuredDuration = AudioTrimService.playableDuration(of: audioURL)
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
            let measuredDuration = AudioTrimService.playableDuration(of: audioURL)
            let duration = measuredDuration > 0 ? measuredDuration : checkpoint.duration
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
        recorderHasFinished = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        syncDurationFromRecorder()
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
            if !recorderHasFinished {
                qualityWarning = nil
            }
        }
    }

    private func persistCheckpoint() {
        guard let noteId = currentNoteId, let temp = tempURL else { return }
        syncDurationFromRecorder()
        try? storage.saveCheckpoint(
            sessionId: sessionId,
            noteId: noteId,
            tempAudioPath: temp.path,
            duration: duration
        )
        persistActiveSession()
    }

    /// Use the recorder clock only — never probe partial temp AAC files while a session is open.
    private func syncDurationFromRecorder() {
        if let recorderTime = recorder?.currentTime, recorderTime.isFinite, recorderTime > duration {
            duration = recorderTime
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
        center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppTermination()
            }
        }
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func handleAppBackgrounding() {
        guard state != .idle else { return }
        syncDurationFromRecorder()
        persistCheckpoint()
    }

    private func handleAppForegrounding() {
        guard state != .idle else { return }
        syncDurationFromRecorder()

        guard state == .recording, !recorderHasFinished else {
            if state == .recording, timer == nil {
                startTimer()
            }
            return
        }

        if recorder?.isRecording == true {
            if timer == nil { startTimer() }
            return
        }

        do {
            try configureAudioSession()
            if recorder?.record() == true {
                if timer == nil { startTimer() }
                qualityWarning = nil
                return
            }
        } catch {
            // Fall through to paused state below.
        }

        state = .paused
        timer?.invalidate()
        qualityWarning = "Recording was interrupted. Tap Stop to save, or Resume to continue."
        persistCheckpoint()
    }

    private func handleAppTermination() {
        guard state != .idle else { return }
        syncDurationFromRecorder()
        persistCheckpoint()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            syncDurationFromRecorder()
            persistCheckpoint()
            if state == .recording, !recorderHasFinished {
                recorder?.pause()
                state = .paused
                timer?.invalidate()
                qualityWarning = "Recording paused (phone call or system interruption). Tap Resume when ready."
            }
        case .ended:
            guard state == .paused, !recorderHasFinished,
                  let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private static let activeSessionKey = "com.paperorg.notes.activeRecordingSession"

    private func persistActiveSession() {
        guard let noteId = currentNoteId, let temp = tempURL else { return }
        let payload = ActiveRecordingSession(
            noteId: noteId,
            sessionId: sessionId,
            tempAudioPath: temp.path,
            updatedAt: .now
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.activeSessionKey)
        }
    }

    private func clearActiveSession() {
        UserDefaults.standard.removeObject(forKey: Self.activeSessionKey)
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

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if isStoppingIntentionally {
                syncDurationFromRecorder()
                stopFinishContinuation?.resume()
                stopFinishContinuation = nil
                return
            }

            guard state == .recording || state == .paused else { return }

            recorderHasFinished = true
            syncDurationFromRecorder()
            persistCheckpoint()

            if state == .recording {
                state = .paused
                timer?.invalidate()
            }

            qualityWarning = flag
                ? "Recording stopped unexpectedly. Tap Stop to save."
                : "Recording failed — tap Stop to save what was captured."
        }
    }
}

private struct ActiveRecordingSession: Codable {
    let noteId: UUID
    let sessionId: UUID
    let tempAudioPath: String
    let updatedAt: Date
}
