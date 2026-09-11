import AVFoundation
import Foundation
import Observation
import UIKit

enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case paused
}

enum RecordingLengthPolicy {
    static let freeMinutes = 3
    static let proMinutes = 180

    static func shouldStop(duration: TimeInterval, maxMinutes: Int) -> Bool {
        guard maxMinutes > 0 else { return false }
        return duration >= Double(maxMinutes) * 60
    }

    /// Release talks to Platform for usage, which may omit the cap field.
    /// Without a client default, a Free session would record until the server
    /// 413s after upload.
    static func capMinutes(from usage: ProUsageInfo?, isPro: Bool) -> Int {
        if let minutes = usage?.maxRecordingMinutes, minutes > 0 {
            return minutes
        }
        return isPro ? proMinutes : freeMinutes
    }
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

    private var recorder: ContinuousAudioRecorder?
    var onSegmentReady: ((UUID) -> Void)?
    private var timer: Timer?
    private var tempURL: URL?
    private let storage: StorageService
    private var lowLevelStart: Date?
    private var recorderHasFinished = false
    private var pendingAudioSessionDeactivation: Task<Void, Never>?
    private var maxRecordingMinutes = 0
    private var recoveringSessionIDs: Set<UUID> = []
    private(set) var didReachRecordingCap = false

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

    func start(noteId: UUID, maxRecordingMinutes: Int = RecordingLengthPolicy.freeMinutes) async throws {
        guard state == .idle else { throw RecordingError.alreadyRecording }
        self.maxRecordingMinutes = maxRecordingMinutes
        didReachRecordingCap = false

        let granted = await requestPermission()
        guard granted else { throw RecordingError.permissionDenied }

        do {
            pendingAudioSessionDeactivation?.cancel()
            pendingAudioSessionDeactivation = nil
            try configureAudioSession()

            sessionId = UUID()
            currentNoteId = noteId
            recorderHasFinished = false
            tempURL = storage.recordingsDirectory.appendingPathComponent("temp-\(sessionId.uuidString).caf")

            guard let url = tempURL else { throw RecordingError.setupFailed("Invalid temp URL") }

            let directory = storage.segmentDirectory(for: noteId)
            try SegmentRecordingStore(directory: directory).saveSession(sessionId)
            recorder = try ContinuousAudioRecorder(url: url, directory: directory,
                maximumSeconds: Double(maxRecordingMinutes) * 60,
                onChunk: { [weak self] in self?.onSegmentReady?(noteId) },
                onCap: { [weak self] in
                    guard let self else { return }
                    self.recorder?.releaseInput()
                    self.syncDurationFromRecorder()
                    self.recorderHasFinished = true
                    self.state = .paused
                    self.timer?.invalidate()
                    self.didReachRecordingCap = true
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    self.pause()
                    self.recorder?.releaseInput()
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    self.recorderHasFinished = true
                    self.qualityWarning = "Capture stopped: \(error.localizedDescription). Tap Stop to save."
                })
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
            releaseRecorderAndDeactivateAudioSession()
            resetState()
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

        defer {
            releaseRecorderAndDeactivateAudioSession()

            // A failed finalization must not leave the microphone reserved or
            // make the next recording appear to still be in progress. The
            // checkpoint remains available for recovery in that case.
            if state != .idle {
                resetState()
            }
        }

        timer?.invalidate()
        timer = nil

        var captureFailure: Error?
        do { try recorder?.finish() } catch { captureFailure = error }
        syncDurationFromRecorder()
        // Foreground/interruption notifications must not reactivate the record
        // session while the detached archive export is still finishing.
        recorderHasFinished = true
        state = .paused
        releaseRecorderAndDeactivateAudioSession()
        let encoded = storage.recordingsDirectory.appendingPathComponent("temp-\(sessionId.uuidString).m4a")
        try await Task.detached(priority: .userInitiated) {
            try ContinuousSegmentWriter.encodeArchive(temp, to: encoded)
        }.value
        guard currentNoteId == noteId, storage.loadCheckpoint(sessionId: sessionId) != nil else {
            try? FileManager.default.removeItem(at: encoded)
            throw CancellationError()
        }
        let finalURL = try storage.finalizeRecording(from: encoded, noteId: noteId)
        if captureFailure == nil {
            try SegmentRecordingStore(directory: storage.segmentDirectory(for: noteId)).markCaptureFinished()
            try? FileManager.default.removeItem(at: temp)
            storage.deleteCheckpoint(sessionId: sessionId)
            clearActiveSession()
        }

        let playableDuration = AudioTrimService.playableDuration(of: finalURL)
        let finalDuration = playableDuration > 0 ? playableDuration : duration

        resetState()
        if let captureFailure { throw captureFailure }
        return (noteId, finalURL, finalDuration)
    }

    func cancel() {
        defer {
            releaseRecorderAndDeactivateAudioSession()
            resetState()
        }

        try? recorder?.finish()
        timer?.invalidate()
        if let temp = tempURL { try? FileManager.default.removeItem(at: temp) }
        if let currentNoteId { storage.deleteAudio(for: currentNoteId) }
        storage.deleteCheckpoint(sessionId: sessionId)
        clearActiveSession()
    }

    /// Finalizes recordings left behind by an interrupted app session.
    func recoverInterruptedRecordings(excludingSessionId activeSessionId: UUID? = nil) async -> [RecoveredRecording] {
        var recovered: [RecoveredRecording] = []
        for checkpoint in storage.loadPendingCheckpoints() {
            if checkpoint.sessionId == activeSessionId { continue }
            if state != .idle,
               checkpoint.sessionId == sessionId || checkpoint.noteId == currentNoteId {
                continue
            }
            if let result = await recover(checkpoint: checkpoint) { recovered.append(result) }
        }
        return recovered
    }

    func recoverRecording(for noteId: UUID) async -> RecoveredRecording? {
        if state != .idle, noteId == currentNoteId { return nil }
        if let existing = existingRecording(for: noteId) {
            return existing
        }
        guard let checkpoint = storage.loadPendingCheckpoints().first(where: { $0.noteId == noteId }) else {
            return nil
        }
        return await recover(checkpoint: checkpoint)
    }

    func existingRecording(for noteId: UUID) -> RecoveredRecording? {
        let audioURL = storage.audioURL(for: noteId)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return nil }
        let measuredDuration = AudioTrimService.playableDuration(of: audioURL)
        guard measuredDuration > 0 else { return nil }
        return RecoveredRecording(noteId: noteId, audioURL: audioURL, duration: measuredDuration)
    }

    private func recover(checkpoint: RecordingCheckpoint) async -> RecoveredRecording? {
        guard !recoveringSessionIDs.contains(checkpoint.sessionId) else { return nil }
        recoveringSessionIDs.insert(checkpoint.sessionId)
        defer { recoveringSessionIDs.remove(checkpoint.sessionId) }
        let temporaryURL = URL(fileURLWithPath: checkpoint.tempAudioPath)
        let expectedPrefix = storage.recordingsDirectory.path + "/temp-"
        guard temporaryURL.path.hasPrefix(expectedPrefix),
              FileManager.default.fileExists(atPath: temporaryURL.path) else {
            storage.deleteCheckpoint(sessionId: checkpoint.sessionId)
            return nil
        }

        do {
            let finalizedSource: URL
            if temporaryURL.pathExtension == "caf" {
                finalizedSource = temporaryURL.deletingPathExtension().appendingPathExtension("m4a")
                let directory = storage.segmentDirectory(for: checkpoint.noteId)
                try await Task.detached(priority: .utility) {
                    try ContinuousSegmentWriter.encodeArchive(temporaryURL, to: finalizedSource)
                    try Self.recoverTail(directory: directory, archiveURL: temporaryURL)
                }.value
            } else {
                finalizedSource = temporaryURL
            }
            guard storage.loadCheckpoint(sessionId: checkpoint.sessionId) != nil else {
                try? FileManager.default.removeItem(at: finalizedSource)
                try? FileManager.default.removeItem(at: storage.segmentDirectory(for: checkpoint.noteId))
                return nil
            }
            let audioURL = try storage.finalizeRecording(from: finalizedSource, noteId: checkpoint.noteId)
            if temporaryURL.pathExtension == "caf" {
                try SegmentRecordingStore(directory: storage.segmentDirectory(for: checkpoint.noteId)).markCaptureFinished()
            }
            if temporaryURL != finalizedSource { try? FileManager.default.removeItem(at: temporaryURL) }
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
        didReachRecordingCap = false
        maxRecordingMinutes = 0
    }

    nonisolated private static func recoverTail(directory: URL, archiveURL: URL) throws {
        let store = SegmentRecordingStore(directory: directory)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw CancellationError() }
        let chunks = try store.chunks()
        let start = chunks.last.map { $0.startSeconds + $0.duration } ?? 0
        let file = try AVAudioFile(forReading: archiveURL)
        let total = Double(file.length) / file.processingFormat.sampleRate
        guard total > start + 0.01 else { return }
        let index = chunks.count
        let name = "\(index).m4a"
        try ContinuousSegmentWriter.encodeArchive(archiveURL, to: store.directory.appendingPathComponent(name), startSeconds: start)
        try store.saveChunk(RecordingAudioChunk(index: index, startSeconds: start, duration: total - start, fileName: name))
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // This view never plays while it records. Using the record-only
        // category avoids retaining the VoIP-style speaker/Bluetooth route
        // that .playAndRecord configures for calls.
        try session.setCategory(
            .record,
            mode: .measurement,
            options: []
        )
        try session.setActive(true)
    }

    /// AVAudioRecorder can retain the input route until it is released. Clear
    /// it before deactivation, otherwise iOS may reject deactivation as busy
    /// and leave the system microphone unavailable to other apps.
    private func releaseRecorderAndDeactivateAudioSession() {
        recorder?.releaseInput()
        recorder = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // The route can still be unwinding immediately after stop(). Retry
            // once, but cancel that retry when a new recording is started.
            pendingAudioSessionDeactivation?.cancel()
            pendingAudioSessionDeactivation = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, self?.state != .recording else { return }
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
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

        stopIfOverRecordingCap()
    }

    private func stopIfOverRecordingCap() {
        guard !didReachRecordingCap else { return }
        guard RecordingLengthPolicy.shouldStop(
            duration: duration,
            maxMinutes: maxRecordingMinutes
        ) else { return }
        didReachRecordingCap = true
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
        // The app declares the audio background mode so an active recording can
        // continue when the screen locks. Once recording has stopped, however,
        // it must not retain its recording session while idle in the background.
        // A screen lock after processing otherwise leaves the app eligible to
        // keep the input route, preventing Voice Memos and the next recording
        // from acquiring the microphone.
        guard state != .idle else {
            releaseRecorderAndDeactivateAudioSession()
            return
        }
        syncDurationFromRecorder()
        persistCheckpoint()
    }

    private func handleAppForegrounding() {
        guard state != .idle else { return }
        syncDurationFromRecorder()
        if let currentNoteId { onSegmentReady?(currentNoteId) }

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

    private static let activeSessionKey = "com.paperorg.voicenotes.activeRecordingSession"

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

@MainActor
private final class ContinuousAudioRecorder {
    private let engine = AVAudioEngine()
    private let sink: SegmentCaptureSink
    private var hasTap = false
    private var hasFinished = false
    var isRecording: Bool { engine.isRunning }
    var currentTime: Double { sink.duration }
    func updateMeters() {}
    func averagePower(forChannel: Int) -> Float { sink.level }

    init(url: URL, directory: URL, maximumSeconds: Double,
         onChunk: @escaping @MainActor () -> Void,
         onCap: @escaping @MainActor () -> Void,
         onFailure: @escaping @MainActor (Error) -> Void) throws {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingError.setupFailed("Microphone is unavailable")
        }
        let writer = try ContinuousSegmentWriter(directory: directory, archiveURL: url,
            format: format, maximumSeconds: maximumSeconds)
        writer.onChunk = { Task { @MainActor in onChunk() } }
        writer.onCap = { Task { @MainActor in onCap() } }
        sink = SegmentCaptureSink(writer: writer, onFailure: onFailure)
        let sink = self.sink
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            sink.enqueue(buffer)
        }
        hasTap = true
    }

    func prepareToRecord() -> Bool { engine.prepare(); return true }
    func record() -> Bool {
        guard !hasFinished else { return false }
        do { try engine.start(); return true } catch { return false }
    }
    func pause() { engine.pause() }
    func finish() throws {
        releaseInput()
        guard !hasFinished else { return }
        hasFinished = true
        try sink.finish()
    }
    func releaseInput() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
    }
}

/// A bounded serial disk queue keeps I/O and AAC encoding off the realtime tap.
/// Overflow is an explicit recording failure, never silently dropped audio.
private final class SegmentCaptureSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.paperorg.notes.segment-capture", qos: .userInitiated)
    private let lock = NSLock()
    private var pending = 0
    private var failure: Error?
    private var meter: Float = -160
    private let writer: ContinuousSegmentWriter
    private let onFailure: @MainActor (Error) -> Void
    var duration: Double { queue.sync { writer.duration } }
    var level: Float { queue.sync { meter } }
    init(writer: ContinuousSegmentWriter, onFailure: @escaping @MainActor (Error) -> Void) {
        self.writer = writer
        self.onFailure = onFailure
    }
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard pending < 64 else {
            lock.unlock()
            queue.async { self.fail(RecordingError.saveFailed("Audio storage could not keep up.")) }
            return
        }
        pending += 1
        lock.unlock()
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = copy.floatChannelData else {
            lock.lock(); pending -= 1; lock.unlock()
            queue.async { self.fail(RecordingError.saveFailed("Could not buffer microphone audio.")) }
            return
        }
        copy.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel], count: Int(buffer.frameLength))
        }
        queue.async {
            defer { self.lock.lock(); self.pending -= 1; self.lock.unlock() }
            guard self.failure == nil else { return }
            do {
                try self.writer.append(copy)
                let samples = copy.floatChannelData![0]
                var sum: Float = 0
                for index in 0..<Int(copy.frameLength) { sum += samples[index] * samples[index] }
                self.meter = 20 * log10(max(0.00000001, sqrt(sum / Float(max(1, copy.frameLength)))))
            } catch { self.fail(error) }
        }
    }
    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        Task { @MainActor in self.onFailure(error) }
    }
    func finish() throws {
        try queue.sync {
            try writer.finish()
            if let failure { throw failure }
        }
    }
}

/// Called only by the capture queue. Rotation closes a file, not the microphone.
/// The CAF archive remains readable after a process crash; final M4A is produced
/// off the main actor once capture has released the input route.
final class ContinuousSegmentWriter: @unchecked Sendable {
    private let directory: URL
    private let format: AVAudioFormat
    private let segmentFrames: AVAudioFramePosition
    private let maximumFrames: AVAudioFramePosition
    private var archive: AVAudioFile?
    private var chunkFile: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var chunkFrames: AVAudioFramePosition = 0
    private var index = 0
    private var finished = false
    var duration: Double { Double(frames) / format.sampleRate }
    var onChunk: (@Sendable () -> Void)?
    var onCap: (@Sendable () -> Void)?

    init(directory: URL, archiveURL: URL, format: AVAudioFormat, segmentSeconds: Double = 120, maximumSeconds: Double) throws {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingError.setupFailed("Unsupported microphone format")
        }
        self.directory = directory
        self.format = format
        segmentFrames = max(1, AVAudioFramePosition(segmentSeconds * format.sampleRate))
        maximumFrames = maximumSeconds > 0 ? AVAudioFramePosition(maximumSeconds * format.sampleRate) : .max
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.checkDiskSpace(at: directory, requiredBytes: 256 * 1024 * 1024)
        // Integer PCM halves archive size without sacrificing speech fidelity.
        archive = try AVAudioFile(forWriting: archiveURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard !finished, frames < maximumFrames else { return }
        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength && frames < maximumFrames {
            let count = AVAudioFrameCount(min(Int64(buffer.frameLength - offset), segmentFrames - chunkFrames, maximumFrames - frames))
            guard let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let source = buffer.floatChannelData, let target = slice.floatChannelData else {
                throw RecordingError.setupFailed("Unsupported microphone format")
            }
            slice.frameLength = count
            for channel in 0..<Int(format.channelCount) {
                target[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
            }
            if chunkFile == nil {
                try Self.checkDiskSpace(at: directory, requiredBytes: 256 * 1024 * 1024)
                chunkFile = try AVAudioFile(forWriting: directory.appendingPathComponent("\(index).m4a"), settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ])
            }
            try archive?.write(from: slice)
            try chunkFile?.write(from: slice)
            frames += Int64(count)
            chunkFrames += Int64(count)
            offset += count
            if chunkFrames == segmentFrames { try closeChunk() }
            if frames == maximumFrames { onCap?() }
        }
    }

    func finish() throws {
        guard !finished else { return }
        finished = true
        archive = nil
        try closeChunk()
    }

    private func closeChunk() throws {
        guard chunkFrames > 0 else { return }
        chunkFile = nil // Flush the codec/container before committing the queue entry.
        let chunk = RecordingAudioChunk(index: index,
            startSeconds: Double(frames - chunkFrames) / format.sampleRate,
            duration: Double(chunkFrames) / format.sampleRate, fileName: "\(index).m4a")
        try SegmentRecordingStore(directory: directory).saveChunk(chunk)
        index += 1
        chunkFrames = 0
        onChunk?()
    }

    static func encodeArchive(_ source: URL, to destination: URL, startSeconds: Double = 0) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let seconds = Double(input.length) / format.sampleRate
        try checkDiskSpace(at: destination.deletingLastPathComponent(), requiredBytes: Int64(seconds * 32_000) + 64 * 1024 * 1024)
        input.framePosition = AVAudioFramePosition(startSeconds * format.sampleRate)
        let output = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw RecordingError.setupFailed("Could not read captured audio")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }

    private static func checkDiskSpace(at directory: URL, requiredBytes: Int64) throws {
        if let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < requiredBytes {
            throw RecordingError.saveFailed("Not enough storage to continue recording. Captured audio has been kept.")
        }
    }
}

private struct ActiveRecordingSession: Codable {
    let noteId: UUID
    let sessionId: UUID
    let tempAudioPath: String
    let updatedAt: Date
}
