import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudioImportError: LocalizedError, Equatable {
    case unreadable
    case tooShort
    case tooLong(limitMinutes: Int)
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return L10n.Import.errorUnreadable
        case .tooShort:
            return L10n.Import.errorTooShort
        case .tooLong(let limitMinutes):
            return L10n.Import.errorTooLong(limitMinutes)
        case .conversionFailed:
            return L10n.Import.errorConversionFailed
        }
    }
}

enum ImportPickerResult {
    static func userFacingError(from error: Error) -> String? {
        if error is CancellationError { return nil }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return nil
        }
        return error.localizedDescription
    }
}

/// Brings an existing audio file into a note's own storage slot.
///
/// Everything downstream — playback, the email attachment, the GDPR export —
/// addresses audio as `{noteId}.m4a`, so an import is converted rather than
/// stored in its original container. That also keeps long imports uploadable:
/// WAV runs about 10 MB per minute, which the server's 100 MB ceiling cuts off
/// after roughly nine minutes, while AAC fits hours into the same budget.
enum AudioImportService {
    static let supportedTypes: [UTType] = [.mp3, .wav, .mpeg4Audio]

    /// Formats AVFoundation can already store as-is, needing only a copy.
    private static let passThroughExtensions: Set<String> = ["m4a", "mp4", "m4b"]

    @MainActor
    static func importAudio(
        from source: URL,
        noteId: UUID,
        storage: StorageService,
        maximumMinutes: Int
    ) async throws -> TimeInterval {
        // A file chosen outside the sandbox is only readable inside this scope.
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration),
              duration.isNumeric,
              try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw AudioImportError.unreadable
        }

        let seconds = CMTimeGetSeconds(duration)
        guard seconds >= 0.5 else { throw AudioImportError.tooShort }
        // Refuse before converting: the server enforces the same cap, but only
        // after the whole file has been uploaded.
        if maximumMinutes > 0, seconds > Double(maximumMinutes) * 60 {
            throw AudioImportError.tooLong(limitMinutes: maximumMinutes)
        }

        let destination = storage.audioURL(for: noteId)
        if passThroughExtensions.contains(source.pathExtension.lowercased()) {
            try copy(from: source, to: destination)
        } else {
            try await convertToM4A(asset: asset, destination: destination)
        }
        return seconds
    }

    private static func copy(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
    }

    private static func convertToM4A(asset: AVURLAsset, destination: URL) async throws {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioImportError.conversionFailed
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        session.outputURL = destination
        session.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            try? fileManager.removeItem(at: destination)
            throw AudioImportError.conversionFailed
        }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
    }
}
