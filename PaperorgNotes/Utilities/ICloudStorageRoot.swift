import Foundation

/// Shared iCloud container for SwiftData (CloudKit) and on-disk audio/checkpoints.
enum ICloudStorageRoot {
    static var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: AppConstants.cloudKitContainerID)
    }

    static var isAvailable: Bool {
        containerURL != nil
    }

    static func paperorgDirectory(createIfNeeded: Bool = true) -> URL? {
        guard let root = containerURL else { return nil }
        let directory = root.appendingPathComponent("PaperorgNotes", isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// One-time copy of local recordings into the iCloud container when sync becomes available.
    static func migrateLocalFilesToICloudIfNeeded(from localRoot: URL) {
        guard let cloudRoot = paperorgDirectory() else { return }
        guard localRoot.standardizedFileURL != cloudRoot.standardizedFileURL else { return }

        let fileManager = FileManager.default
        let migratedKey = "com.paperorg.voicenotes.icloudStorageMigrated"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        let subfolders = ["Recordings", "Checkpoints", "Exports", "Branding"]
        for name in subfolders {
            let source = localRoot.appendingPathComponent(name, isDirectory: true)
            let destination = cloudRoot.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files {
                let target = destination.appendingPathComponent(file.lastPathComponent)
                guard !fileManager.fileExists(atPath: target.path) else { continue }
                try? fileManager.copyItem(at: file, to: target)
            }
        }

        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
