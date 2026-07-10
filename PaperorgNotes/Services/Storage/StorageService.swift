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
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: dir.path
            )
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

    func loadPendingCheckpoints() -> [RecordingCheckpoint] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: checkpointsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.compactMap { url in
            guard url.pathExtension == "checkpoint",
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? JSONDecoder().decode(RecordingCheckpoint.self, from: data)
        }
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
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }
    
    func readAudioData(for noteId: UUID) throws -> Data {
        try AudioFileReader.readData(from: audioURL(for: noteId))
    }
    
    func prepareAudioForReading(noteId: UUID) {
        AudioFileReader.prepareForReading(audioURL(for: noteId))
    }
    
    func deleteAudio(for noteId: UUID) {
        let url = audioURL(for: noteId)
        try? fileManager.removeItem(at: url)
    }
    
    func deleteAllAudio() {
        guard let files = try? fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    func deleteAllLocalData() {
        for directory in [recordingsDirectory, checkpointsDirectory, exportsDirectory, gdprDirectory] {
            guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        encryption.deleteKey()
    }

    func purgeExpiredAudio(notes: [Note], retentionDays: Int?) {
        guard let retentionDays, retentionDays > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        for note in notes where note.createdAt < cutoff && note.audioDeletedAt == nil {
            deleteAudio(for: note.id)
            note.audioDeletedAt = .now
            note.updatedAt = .now
        }
    }

    func deleteExportArtifact(at url: URL) throws {
        let allowedDirectories = [exportsDirectory, gdprDirectory]
        guard allowedDirectories.contains(where: { url.path.hasPrefix($0.path + "/") }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    func purgeExportArtifacts(olderThan cutoff: Date) -> [URL] {
        var removed: [URL] = []
        for directory in [exportsDirectory, gdprDirectory] {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true,
                      let modified = values?.contentModificationDate,
                      modified < cutoff else {
                    continue
                }
                if (try? fileManager.removeItem(at: file)) != nil {
                    removed.append(file)
                }
            }
        }
        return removed
    }
    
    func exportGDPRArchive(notes: [Note]) throws -> URL {
        let exportId = UUID()
        let tempDir = gdprDirectory.appendingPathComponent("export-\(exportId.uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        
        let metadata = notes.map { note -> [String: Any] in
            [
                "id": note.id.uuidString,
                "title": note.title,
                "createdAt": ISO8601DateFormatter().string(from: note.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: note.updatedAt),
                "durationSeconds": note.durationSeconds,
                "language": note.language,
                "outputType": note.outputType,
                "status": note.status,
                "projectName": note.projectName ?? "",
                "primaryProvider": note.primaryProvider ?? "",
                "rawTranscript": note.rawTranscript ?? "",
                "correctedTranscript": note.correctedTranscript ?? "",
                "summaryShort": note.summaryShort ?? "",
                "summaryDetailed": note.summaryDetailed ?? "",
                "structuredOutput": note.structuredOutputJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                "qualityReport": note.qualityReportJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                "segments": note.segments.sorted { $0.segmentIndex < $1.segmentIndex }.map {
                    [
                        "index": $0.segmentIndex,
                        "text": $0.text,
                        "startTime": $0.startTime,
                        "endTime": $0.endTime,
                        "confidence": $0.confidence,
                        "speaker": $0.speakerLabel ?? ""
                    ]
                },
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
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        var archive = Data()
        var centralDirectory = Data()

        for file in files {
            let fileData = try Data(contentsOf: file)
            let name = file.lastPathComponent
            let nameData = Data(name.utf8)
            let crc = CRC32.checksum(fileData)
            let localOffset = UInt32(archive.count)

            archive.appendLE(UInt32(0x04034B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc)
            archive.appendLE(UInt32(fileData.count))
            archive.appendLE(UInt32(fileData.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(fileData)

            centralDirectory.appendLE(UInt32(0x02014B50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(UInt32(fileData.count))
            centralDirectory.appendLE(UInt32(fileData.count))
            centralDirectory.appendLE(UInt16(nameData.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(localOffset)
            centralDirectory.append(nameData)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLE(UInt32(0x06054B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(files.count))
        archive.appendLE(UInt16(files.count))
        archive.appendLE(UInt32(centralDirectory.count))
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        try archive.write(to: destination, options: .atomic)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xedb8_8320 : value >> 1
            }
        }
        return value ^ 0xffff_ffff
    }
}
