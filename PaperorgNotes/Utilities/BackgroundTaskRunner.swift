#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import BackgroundTasks
#endif

#if canImport(UIKit)
@MainActor
private final class BackgroundTaskHandle: @unchecked Sendable {
    private let application: UIApplication
    var identifier = UIBackgroundTaskIdentifier.invalid

    init(application: UIApplication) {
        self.application = application
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif

/// Reports chunk progress to the system UI that keeps a transcription running
/// after the user leaves the app. With no system task attached, updates do nothing.
@MainActor
final class TranscriptionProgress {
    private var title = ""
    private var completedTask = false
    private var lastCompleted = 0
    private var lastTotal = 1
    private var lastSubtitle = ""
    private(set) var wasCancelled = false
    #if os(iOS)
    private var task: AnyObject?
    private var work: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    #endif

    fileprivate func begin(title: String) {
        self.title = title
    }

    #if os(iOS)
    @available(iOS 26, *)
    fileprivate func attach(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.update(completed: self.lastCompleted, total: self.lastTotal, subtitle: self.lastSubtitle)
            }
        }
    }

    fileprivate func track(_ work: Task<Void, Never>) {
        self.work = work
    }
    #endif

    func update(completed: Int, total: Int, subtitle: String) {
        lastCompleted = completed
        lastTotal = total
        lastSubtitle = subtitle
        #if os(iOS)
        guard #available(iOS 26, *), let task = task as? BGContinuedProcessingTask else { return }
        let totalCount = Int64(max(total, 1))
        task.progress.totalUnitCount = totalCount
        task.progress.completedUnitCount = Int64(min(max(completed, 0), Int(totalCount)))
        task.updateTitle(title, subtitle: subtitle)
        #endif
    }

    func cancel() {
        wasCancelled = true
        #if os(iOS)
        work?.cancel()
        #endif
    }

    fileprivate func finish(success: Bool) {
        #if os(iOS)
        guard !completedTask, #available(iOS 26, *), let task = task as? BGContinuedProcessingTask else { return }
        completedTask = true
        heartbeat?.cancel()
        heartbeat = nil
        task.setTaskCompleted(success: success)
        self.task = nil
        #endif
    }
}

/// Asks iOS to keep a transcription the user just started running after they leave the app.
@MainActor
enum ContinuedTranscription {
    static let permittedIdentifier = "com.paperorg.voicenotes.transcribe.*"
    private static var didRegister = false
    private static var pending: PendingRun?

    private final class PendingRun {
        let progress: TranscriptionProgress
        let operation: (TranscriptionProgress) async -> Void
        private var resumed = false
        private let continuation: CheckedContinuation<Void, Never>

        init(
            progress: TranscriptionProgress,
            operation: @escaping (TranscriptionProgress) async -> Void,
            continuation: CheckedContinuation<Void, Never>
        ) {
            self.progress = progress
            self.operation = operation
            self.continuation = continuation
        }

        func resume() {
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
    }

    @discardableResult
    static func register() -> Bool {
        #if os(iOS)
        guard #available(iOS 26, *) else { return false }
        if didRegister { return true }
        let accepted = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: permittedIdentifier,
            using: nil
        ) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await deliver(continued)
            }
        }
        // Submitting without a successful registration raises an ObjC exception
        // and kills the app. A failed early attempt must stay retryable.
        if accepted { didRegister = true }
        return accepted
        #else
        return false
        #endif
    }

    /// Runs `operation` immediately. On iOS 26 and later, iOS also keeps that work
    /// alive in the background and shows its progress. If the system refuses, the
    /// work still runs while the app is open.
    static func perform(
        title: String,
        subtitle: String,
        operation: @escaping @MainActor (TranscriptionProgress) async -> Void
    ) async {
        #if os(iOS)
        if #available(iOS 26, *), register() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let progress = TranscriptionProgress()
                progress.begin(title: title)
                progress.update(completed: 0, total: 1, subtitle: subtitle)
                pending = PendingRun(
                    progress: progress,
                    operation: operation,
                    continuation: continuation
                )
                let request = BGContinuedProcessingTaskRequest(
                    identifier: "com.paperorg.voicenotes.transcribe.\(UUID().uuidString)",
                    title: title,
                    subtitle: subtitle
                )
                request.strategy = .fail
                Task {
                    do {
                        try submit(request)
                    } catch {
                        await MainActor.run {
                            startWithoutSystemTask()
                        }
                    }
                }
            }
            return
        }
        #endif
        let progress = TranscriptionProgress()
        progress.begin(title: title)
        await operation(progress)
    }

    #if os(iOS)
    @available(iOS 26, *)
    private static func submit(_ request: BGContinuedProcessingTaskRequest) throws {
        try BGTaskScheduler.shared.submit(request)
    }

    @available(iOS 26, *)
    private static func deliver(_ task: BGContinuedProcessingTask) async {
        guard let pending else {
            task.setTaskCompleted(success: false)
            return
        }
        self.pending = nil
        pending.progress.attach(task)
        let work = Task { @MainActor in
            await pending.operation(pending.progress)
        }
        pending.progress.track(work)
        await work.value
        pending.progress.finish(success: !pending.progress.wasCancelled)
        pending.resume()
    }

    private static func startWithoutSystemTask() {
        guard let pending else { return }
        self.pending = nil
        Task { @MainActor in
            await pending.operation(pending.progress)
            pending.resume()
        }
    }
    #endif
}

/// Holds the screen awake while a transcription is running. Auto-Lock has no
/// Never option on this phone, and the app can override that while it is open.
enum ScreenAwake {
    @MainActor
    static func keepOn<T>(_ operation: () async throws -> T) async rethrows -> T {
        #if os(iOS)
        let wasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = wasDisabled }
        #endif
        return try await operation()
    }
}

/// Keeps async work alive briefly when the user locks the phone mid-stop or mid-processing.
enum BackgroundTaskRunner {
    @MainActor
    static func run<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        #if canImport(UIKit)
        let application = UIApplication.shared
        let handle = BackgroundTaskHandle(application: application)
        handle.identifier = application.beginBackgroundTask(withName: name) {
            Task { @MainActor in
                handle.end()
            }
        }
        defer {
            handle.end()
        }
        #endif
        return try await operation()
    }
}
