#if os(iOS)
import Foundation
import SwiftData
import UIKit
import WatchConnectivity

enum WatchPhoneSetup {
    static let language = "language"
    static let emailState = "emailState"
    static let recipient = "recipient"
    static let outcome = "outcome"
    static let detail = "detail"

    static func context(language: String, sendsEmail: Bool, recipients: [String]) -> [String: String] {
        let cleaned = recipients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let state: String
        if !sendsEmail {
            state = "off"
        } else if cleaned.isEmpty {
            state = "missing"
        } else {
            state = "ready"
        }
        let recipient = cleaned.count > 1 ? "\(cleaned.count) people" : (cleaned.first ?? "")
        return [
            Self.language: language,
            Self.emailState: state,
            Self.recipient: recipient
        ]
    }

    static func clipped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else { return trimmed }
        return String(trimmed.prefix(47)) + "…"
    }
}

enum WatchRecordingTransfer {
    static let recordingIDKey = "recordingID"
    static let durationKey = "duration"
    static let createdAtKey = "createdAt"

    struct Payload: Equatable {
        var recordingID: String
        var duration: TimeInterval
        var createdAt: Date?
    }

    static func payload(metadata: [String: Any]?) -> Payload {
        let rawID = (metadata?[recordingIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = (metadata?[durationKey] as? NSNumber)?.doubleValue ?? 0
        let createdAt: Date?
        if let interval = (metadata?[createdAtKey] as? NSNumber)?.doubleValue, interval > 0 {
            createdAt = Date(timeIntervalSince1970: interval)
        } else {
            createdAt = nil
        }
        return Payload(
            recordingID: rawID.isEmpty ? UUID().uuidString : rawID,
            duration: duration,
            createdAt: createdAt
        )
    }
}

/// Receives a finished watch recording and runs it through the iPhone pipeline.
/// Language, summary, and email all come from the phone's existing settings.
@MainActor
final class WatchRecordingInbox: NSObject, WCSessionDelegate {
    static let shared = WatchRecordingInbox()

    private var environment: AppEnvironment?
    private var container: ModelContainer?
    private var activated = false
    private var draining = false
    private var pending: [Incoming] = []
    private let importedIDsKey = "watch.importedRecordingIDs"

    private struct Incoming {
        var url: URL
        var payload: WatchRecordingTransfer.Payload
    }

    func start(environment: AppEnvironment, container: ModelContainer) {
        self.environment = environment
        self.container = container
        guard !activated, WCSession.isSupported() else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
        pushSetup()
    }

    func pushSetup() {
        guard let settings = environment?.settingsService,
              WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        let sendsEmail = settings.sendEmailAfterTranscription && settings.canAutomaticallySendEmail
        try? WCSession.default.updateApplicationContext(
            WatchPhoneSetup.context(
                language: settings.preferredRecordLanguage.displayName,
                sendsEmail: sendsEmail,
                recipients: settings.emailRecipients
            )
        )
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.pushSetup()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let payload = WatchRecordingTransfer.payload(metadata: file.metadata)
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-\(payload.recordingID).m4a")
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: copy)
        } catch {
            return
        }
        Task { @MainActor in
            self.enqueue(Incoming(url: copy, payload: payload))
        }
    }

    private func enqueue(_ incoming: Incoming) {
        pending.append(incoming)
        guard !draining else { return }
        draining = true
        Task { await drain() }
    }

    private func drain() async {
        defer { draining = false }
        while !pending.isEmpty {
            let incoming = pending.removeFirst()
            await ingest(incoming)
        }
    }

    private func ingest(_ incoming: Incoming) async {
        defer { try? FileManager.default.removeItem(at: incoming.url) }
        guard let environment, let container else { return }
        if alreadyImported(incoming.payload.recordingID) { return }

        let context = container.mainContext
        let settings = environment.settingsService
        let noteID = UUID()
        let destination = environment.storageService.audioURL(for: noteID)

        do {
            try environment.storageService.replaceAudio(at: destination, with: incoming.url)
        } catch {
            report(incoming.payload.recordingID, outcome: "failed", detail: "Couldn't save the recording")
            return
        }

        let measured = AudioTrimService.playableDuration(of: destination)
        let duration = measured > 0 ? measured : incoming.payload.duration
        let language = settings.preferredRecordLanguage
        let note = Note(
            id: noteID,
            createdAt: incoming.payload.createdAt ?? .now,
            durationSeconds: duration,
            audioFileName: "\(noteID.uuidString).m4a",
            language: language,
            outputType: settings.defaultOutputType,
            status: .awaitingTranscription
        )
        if !language.isAutoDetect {
            note.recordingLanguageSegments = [
                RecordingLanguageSegment(languageCode: language.rawValue, startTime: 0)
            ]
        }
        settings.setSummaryWriteLanguage(settings.defaultSummaryWriteLanguage, for: note.id)
        context.insert(note)
        do {
            try context.save()
        } catch {
            environment.storageService.deleteAudio(for: noteID)
            context.delete(note)
            report(incoming.payload.recordingID, outcome: "failed", detail: "Couldn't save the recording")
            return
        }
        rememberImported(incoming.payload.recordingID)

        let cap = RecordingLengthPolicy.capMinutes(
            from: settings.cachedProUsage,
            isPro: environment.subscriptionService.isProActive
        )
        if cap > 0, duration > Double(cap) * 60 {
            note.status = NoteStatus.failed.rawValue
            note.errorMessage = AudioImportError.tooLong(limitMinutes: cap).localizedDescription
            note.updatedAt = .now
            try? context.save()
            report(incoming.payload.recordingID, outcome: "failed", detail: note.errorMessage ?? "Recording is too long")
            return
        }

        let notes = await SessionMerge.split(
            note,
            storage: environment.storageService,
            settings: settings,
            context: context
        )
        await transcribe(
            notes,
            watchRecordingID: incoming.payload.recordingID,
            environment: environment,
            context: context
        )
    }

    private func transcribe(
        _ notes: [Note],
        watchRecordingID: String,
        environment: AppEnvironment,
        context: ModelContext
    ) async {
        let duration = notes.reduce(0) { $0 + $1.durationSeconds }
        let lengthy = LongRecordingTranscription.takesLonger(duration)
        let run: (TranscriptionProgress) async -> Void = { progress in
            let wasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = wasIdleDisabled }
            await BackgroundTaskRunner.run("WatchRecording") {
                do {
                    for note in notes {
                        note.status = NoteStatus.processing.rawValue
                        try context.save()
                        try await environment.processRecordingUseCase.execute(
                            note: note,
                            audioURL: environment.storageService.audioURL(for: note.id),
                            onProgress: { completed, total, waiting in
                                progress.update(
                                    completed: completed,
                                    total: total,
                                    subtitle: waiting
                                        ? L10n.Record.longTranscriptionWaiting
                                        : L10n.Record.longTranscriptionPart(completed, total)
                                )
                            }
                        ) { _ in }
                    }
                    if notes.count > 1 {
                        try await SessionMerge.merge(
                            notes,
                            storage: environment.storageService,
                            settings: environment.settingsService,
                            context: context
                        )
                    }
                } catch {
                    for note in notes where note.noteStatus == .processing {
                        note.status = NoteStatus.failed.rawValue
                        note.errorMessage = error.localizedDescription
                        note.updatedAt = .now
                    }
                    try? context.save()
                }
                await self.finishWatchRecording(watchRecordingID, notes: notes, environment: environment)
            }
        }
        if lengthy {
            await ContinuedTranscription.perform(
                title: L10n.Record.longTranscriptionTitle,
                subtitle: L10n.Record.longTranscriptionStatus,
                operation: run
            )
        } else {
            await run(TranscriptionProgress())
        }
    }

    private enum EmailHandoff {
        case sent
        case skipped(String)
        case failed(String)
    }

    private func finishWatchRecording(
        _ recordingID: String,
        notes: [Note],
        environment: AppEnvironment
    ) async {
        guard let primary = notes.first else {
            report(recordingID, outcome: "failed", detail: "Couldn't save the recording")
            return
        }
        if primary.noteStatus == .waitingForNetwork {
            report(recordingID, outcome: "waiting", detail: "Will retry when online")
            return
        }
        guard primary.noteStatus == .ready else {
            report(recordingID, outcome: "failed", detail: primary.errorMessage ?? "Couldn't transcribe")
            return
        }
        switch await deliverEmail(for: primary, environment: environment) {
        case .sent:
            report(recordingID, outcome: "emailed", detail: "Emailed")
        case .skipped(let reason):
            report(recordingID, outcome: "saved", detail: reason)
        case .failed(let reason):
            report(recordingID, outcome: "failed", detail: reason)
        }
    }

    private func deliverEmail(for note: Note, environment: AppEnvironment) async -> EmailHandoff {
        let settings = environment.settingsService
        if !settings.sendEmailAfterTranscription || !settings.canAutomaticallySendEmail {
            return .skipped("Email is off")
        }
        if settings.emailRecipients.isEmpty {
            return .skipped("No email recipient")
        }
        do {
            let payload = try environment.emailService.buildPayload(
                for: note,
                exportService: environment.exportService
            )
            try await environment.emailDeliveryService.send(payload)
            return .sent
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func report(_ recordingID: String, outcome: String, detail: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [
            WatchRecordingTransfer.recordingIDKey: recordingID,
            WatchPhoneSetup.outcome: outcome,
            WatchPhoneSetup.detail: WatchPhoneSetup.clipped(detail)
        ]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func alreadyImported(_ recordingID: String) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: importedIDsKey) ?? []
        return ids.contains(recordingID)
    }

    private func rememberImported(_ recordingID: String) {
        var ids = UserDefaults.standard.stringArray(forKey: importedIDsKey) ?? []
        guard !ids.contains(recordingID) else { return }
        ids.append(recordingID)
        if ids.count > 200 {
            ids.removeFirst(ids.count - 200)
        }
        UserDefaults.standard.set(ids, forKey: importedIDsKey)
    }
}
#endif
