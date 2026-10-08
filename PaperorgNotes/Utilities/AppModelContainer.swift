import Foundation
import SwiftData

enum AppModelContainer {
    /// SwiftData + CloudKit requires optional attributes/relationships and no unique constraints.
    /// The configuration default is `.automatic`, which turns CloudKit on as soon as the
    /// iCloud entitlement is present and then fails to load (`SwiftDataError` 1) because
    /// `Note.id` is unique. Audio still syncs through `ICloudStorageRoot`. The database stays local.
    private static let cloudKitDatabaseSyncEnabled = false

    static func make() -> Result<ModelContainer, Error> {
        let schema = Schema([
            Note.self,
            TranscriptSegmentModel.self,
            StructuredSectionModel.self
        ])

        let localConfiguration = ModelConfiguration(
            "PaperorgNotes",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        if cloudKitDatabaseSyncEnabled,
           ICloudStorageRoot.isAvailable,
           hasCloudKitEntitlement {
            do {
                let cloudConfiguration = ModelConfiguration(
                    "PaperorgNotes",
                    schema: schema,
                    cloudKitDatabase: .private(AppConstants.cloudKitContainerID)
                )
                return .success(try ModelContainer(for: schema, configurations: [cloudConfiguration]))
            } catch {
                print("CloudKit SwiftData unavailable, using local store: \(error.localizedDescription)")
            }
        }

        do {
            return .success(try ModelContainer(for: schema, configurations: [localConfiguration]))
        } catch {
            return .failure(error)
        }
    }

    /// Removes the SwiftData store only. Recordings live in a different folder and must stay.
    static func destroyLocalStore() {
        let schema = Schema([
            Note.self,
            TranscriptSegmentModel.self,
            StructuredSectionModel.self
        ])
        let url = ModelConfiguration(
            "PaperorgNotes",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        ).url
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(atPath: url.path + "-shm")
        try? fileManager.removeItem(atPath: url.path + "-wal")
    }

    private static var hasCloudKitEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.developer.icloud-container-identifiers" as CFString
        return SecTaskCopyValueForEntitlement(task, key, nil) != nil
        #else
        return false
        #endif
    }
}
