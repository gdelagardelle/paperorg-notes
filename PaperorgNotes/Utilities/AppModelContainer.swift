import Foundation
import SwiftData

enum AppModelContainer {
    /// SwiftData + CloudKit requires optional attributes/relationships and no unique constraints.
    /// Audio/checkpoints still sync through `ICloudStorageRoot`; database sync stays local until schema v3.
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
            allowsSave: true
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
