import AVFoundation
import Foundation
import WatchConnectivity
import WatchKit

enum WatchTransferKey {
    static let recordingID = "recordingID"
    static let duration = "duration"
    static let createdAt = "createdAt"
}

@MainActor
@Observable
final class WatchRecorder {
    static let shared = WatchRecorder()

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var status = "Tap to record"
    private(set) var setupLine = "Open Paperorg on iPhone"
    private var heardResult = false

    private var recorder: AVAudioRecorder?
    private var runtime: WKExtendedRuntimeSession?
    private var tick: Task<Void, Never>?
    private var fileURL: URL?
    private var recordingID: UUID?
    private var startedAt: Date?
    private var waitingToSend = false
    private var lastResultToken = ""
    private let bridge = WatchSessionBridge()
    private let pendingKey = "watch.pendingRecording"

    private struct PendingRecording: Codable {
        var id: UUID
        var createdAt: Date
        var duration: TimeInterval
    }

    var elapsedText: String {
        let total = Int(elapsed.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private init() {
        bridge.owner = self
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = "This watch can't reach an iPhone"
            return
        }
        let session = WCSession.default
        session.delegate = bridge
        session.activate()
        retryPendingSend()
    }

    func toggle() {
        if isRecording {
            stopAndSend()
        } else {
            Task { await start() }
        }
    }

    func startFromWatchFace() {
        guard !isRecording else { return }
        Task { await start() }
    }

    /// Wrist down and the app leaving the screen both end the take and send it.
    func stopBecauseAppLeftForeground() {
        guard isRecording else { return }
        stopAndSend()
    }

    fileprivate func sessionDidActivate() {
        waitingToSend = false
        applyContext(WCSession.default.receivedApplicationContext)
        retryPendingSend()
    }

    fileprivate func applyContext(_ context: [String: Any]) {
        let language = context["language"] as? String ?? ""
        let emailState = context["emailState"] as? String ?? ""
        let recipient = context["recipient"] as? String ?? ""
        guard !language.isEmpty || !emailState.isEmpty else { return }
        switch emailState {
        case "off":
            setupLine = "Email is off"
        case "missing":
            setupLine = "No email recipient"
        default:
            setupLine = recipient.isEmpty ? language : "\(language) · \(recipient)"
        }
    }

    fileprivate func applyResult(recordingID: String, outcome: String, detail: String) {
        guard !isRecording else { return }
        let token = "\(recordingID)|\(outcome)"
        guard token != lastResultToken else { return }
        lastResultToken = token
        heardResult = true
        switch outcome {
        case "emailed":
            status = "Emailed"
            WKInterfaceDevice.current().play(.success)
        case "waiting":
            status = detail.isEmpty ? "Waiting for iPhone" : detail
        case "saved":
            status = detail.isEmpty ? "Saved on iPhone" : detail
        default:
            status = detail.isEmpty ? "Couldn't transcribe" : detail
        }
    }

    fileprivate func transferFinished(_ url: URL, error: Error?) {
        guard let pending = loadPending(), url.lastPathComponent == "\(pending.id.uuidString).m4a" else { return }
        if error != nil {
            waitingToSend = true
            status = "Will retry when the iPhone is nearby"
            return
        }
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        if !isRecording, !heardResult {
            status = "On your iPhone"
        }
    }

    private func start() async {
        guard !isRecording else { return }
        let granted = await requestPermission()
        guard granted else {
            status = "Allow the microphone in Settings"
            return
        }

        let id = UUID()
        let url = recordingsDirectory().appendingPathComponent("\(id.uuidString).m4a")
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default)
            try audio.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            guard recorder.prepareToRecord(), recorder.record() else {
                status = "Could not start the microphone"
                return
            }
            self.recorder = recorder
            fileURL = url
            recordingID = id
            startedAt = Date()
            elapsed = 0
            isRecording = true
            waitingToSend = false
            heardResult = false
            status = "Recording"
            WKInterfaceDevice.current().play(.start)
            beginRuntime()
            beginTick()
        } catch {
            status = "Could not start the microphone"
        }
    }

    func stopAndSend() {
        guard isRecording || recorder != nil else {
            retryPendingSend()
            return
        }
        tick?.cancel()
        tick = nil
        runtime?.invalidate()
        runtime = nil
        let duration = max(recorder?.currentTime ?? 0, elapsed)
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        WKInterfaceDevice.current().play(.stop)

        guard let url = fileURL, let id = recordingID else {
            status = "Nothing was recorded"
            return
        }
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            status = "Too short. Hold and speak."
            return
        }
        let pending = PendingRecording(id: id, createdAt: startedAt ?? Date(), duration: duration)
        save(pending)
        send(url: url, pending: pending)
    }

    private func retryPendingSend() {
        guard !isRecording, let pending = loadPending() else { return }
        let url = recordingsDirectory().appendingPathComponent("\(pending.id.uuidString).m4a")
        guard FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            return
        }
        fileURL = url
        recordingID = pending.id
        startedAt = pending.createdAt
        send(url: url, pending: pending)
    }

    private func send(url: URL, pending: PendingRecording) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            waitingToSend = true
            status = "Waiting for your iPhone"
            return
        }
        guard session.isCompanionAppInstalled else {
            waitingToSend = true
            status = "Install Paperorg Notes on your iPhone"
            return
        }
        session.transferFile(url, metadata: [
            WatchTransferKey.recordingID: pending.id.uuidString,
            WatchTransferKey.duration: pending.duration,
            WatchTransferKey.createdAt: pending.createdAt.timeIntervalSince1970
        ])
        waitingToSend = false
        status = "Sending to your iPhone"
    }

    private func recordingsDirectory() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func save(_ pending: PendingRecording) {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private func loadPending() -> PendingRecording? {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(PendingRecording.self, from: data)
    }

    private func beginRuntime() {
        let session = WKExtendedRuntimeSession()
        session.delegate = bridge
        runtime = session
        session.start()
    }

    private func beginTick() {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRecording else { return }
                self.elapsed = self.recorder?.currentTime ?? (self.elapsed + 1)
            }
        }
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private final class WatchSessionBridge: NSObject, WCSessionDelegate, WKExtendedRuntimeSessionDelegate {
    weak var owner: WatchRecorder?

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.owner?.sessionDidActivate()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        Task { @MainActor in
            self.owner?.transferFinished(url, error: error)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.owner?.applyContext(applicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }

    private func deliver(_ message: [String: Any]) {
        let recordingID = message["recordingID"] as? String ?? ""
        let outcome = message["outcome"] as? String ?? ""
        let detail = message["detail"] as? String ?? ""
        guard !recordingID.isEmpty, !outcome.isEmpty else { return }
        Task { @MainActor in
            self.owner?.applyResult(recordingID: recordingID, outcome: outcome, detail: detail)
        }
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.owner?.stopBecauseAppLeftForeground()
        }
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        guard reason == .expired || reason == .resignedFrontmost else { return }
        Task { @MainActor in
            self.owner?.stopBecauseAppLeftForeground()
        }
    }
}
