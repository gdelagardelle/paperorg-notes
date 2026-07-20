import AppIntents
import Foundation

/// Widget/Siri entry point — sets the app-group flag before the app opens.
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Record"
    static var description = IntentDescription("Start a voice note in Paperorg Notes.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        QuickRecordSharedStore.markPending()
        return .result()
    }
}

enum QuickRecordSharedStore {
    static let appGroupID = "group.com.paperorg.notes"
    static let pendingKey = "pendingQuickRecord"
    static let requestedAtKey = "quickRecordRequestedAt"

    static func markPending() {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(true, forKey: pendingKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: requestedAtKey)
    }
}
