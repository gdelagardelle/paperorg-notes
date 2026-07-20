import Foundation

enum QuickRecordSharedStore {
    static let appGroupID = "group.com.paperorg.notes"
    static let pendingKey = "pendingQuickRecord"
    static let requestedAtKey = "quickRecordRequestedAt"
    static let recordURL = URL(string: "paperorgnotes://record")!

    static func markPending() {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(true, forKey: pendingKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: requestedAtKey)
    }
}
