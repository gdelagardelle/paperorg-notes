import Foundation
import SwiftData

@MainActor
final class StorageService {
    private let fileManager = FileManager.default
    private let encryption = EncryptionService()
    
    var recordingsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }
    
    var checkpointsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Checkpoints", isDirectory: true)
    }
    
    var exportsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Exports", isDirectory: true)
    }
    
    var gdprDirectory: URL {
        appSupportDirectory.appendingPathComponent("GDPR", isDirectory: true)
    }
    
    private var appSupportDirectory: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperorgNotes", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    init() {
        for dir in [recordingsDirectory, checkpointsDirectory, exportsDirectory, gdprDirectory] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    func audioURL(for noteId: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(noteId.uuidString).m4a")
    }
    
    func checkpointURL(sessionId: UUID) -> URL {
        checkpointsDirectory.appendingPathComponent("\(sessionId.uuidString).checkpoint")
    }
    
    func saveCheckpoint(sessionId: UUID, noteId: UUID, tempAudioPath: String, duration: Double) throws {
        let checkpoint = RecordingCheckpoint(
            sessionId: sessionId,
            noteId: noteId,
            tempAudioPath: tempAudioPath,
            duration: duration,
            updatedAt: .now
        )
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: checkpointURL(sessionId: sessionId), options: .atomic)
    }
    
    func loadCheckpoint(sessionId: UUID) -> RecordingCheckpoint? {
        guard let data = try? Data(contentsOf: checkpointURL(sessionId: sessionId)) else { return nil }
        return try? JSONDecoder().decode(RecordingCheckpoint.self, from: data)
    }
    
    func deleteCheckpoint(sessionId: UUID) {
        try? fileManager.removeItem(at: checkpointURL(sessionId: sessionId))
    }
    
    func finalizeRecording(from tempURL: URL, noteId: UUID) throws -> URL {
        let destination = audioURL(for: noteId)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        return destination
    }
    
    func deleteAudio(for noteId: UUID) {
        let url = audioURL(for: noteId)
        try? fileManager.removeItem(at: url)
    }
    
    func deleteAllAudio() {
        guard let files = try? fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }
    
    func exportGDPRArchive(notes: [Note]) throws -> URL {
        let exportId = UUID()
        let tempDir = gdprDirectory.appendingPathComponent("export-\(exportId.uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let metadata = notes.map { note -> [String: Any] in
            [
                "id": note.id.uuidString,
                "title": note.title,
                "createdAt": ISO8601DateFormatter().string(from: note.createdAt),
                "language": note.language,
                "rawTranscript": note.rawTranscript ?? "",
                "correctedTranscript": note.correctedTranscript ?? "",
                "summaryShort": note.summaryShort ?? "",
                "tags": note.tags
            ]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try jsonData.write(to: tempDir.appendingPathComponent("notes.json"))
        
        for note in notes {
            let audio = audioURL(for: note.id)
            if fileManager.fileExists(atPath: audio.path) {
                try? fileManager.copyItem(at: audio, to: tempDir.appendingPathComponent("\(note.id.uuidString).m4a"))
            }
        }
        
        let zipURL = gdprDirectory.appendingPathComponent("paperorg-export-\(Int(Date.now.timeIntervalSince1970)).zip")
        try ZipUtility.zip(directory: tempDir, to: zipURL)
        try? fileManager.removeItem(at: tempDir)
        return zipURL
    }
}

struct RecordingCheckpoint: Codable {
    let sessionId: UUID
    let noteId: UUID
    let tempAudioPath: String
    let duration: Double
    let updatedAt: Date
}

enum ZipUtility {
    static func zip(directory: URL, to destination: URL) throws {
        // Minimal zip: copy directory contents as folder export for MVP
        // Production: use Compression framework or third-party zip
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: directory, to: destination.deletingPathExtension())
    }
}
