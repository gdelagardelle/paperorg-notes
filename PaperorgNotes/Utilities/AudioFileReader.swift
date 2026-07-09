import Foundation

enum AudioFileReader {
    /// Reads recorded audio, relaxing overly strict file protection when needed.
    static func readData(from url: URL) throws -> Data {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        prepareForReading(url)
        
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TranscriptionError.providerError(
                "Could not read audio file: \(error.localizedDescription)"
            )
        }
    }
    
    static func prepareForReading(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}
