import Foundation
import SwiftUI

@Observable
@MainActor
final class DeepLinkHandler {
    var pendingQuickRecord = false
    var selectedTab = 0

    func handle(_ url: URL) {
        guard url.scheme == AppConstants.urlScheme else { return }

        switch url.host {
        case "record":
            markQuickRecordPending(clearingPreferences: true)
        default:
            break
        }
    }

    func consumeAppGroupQuickRecordFlag() {
        let defaults = appGroupDefaults
        if defaults.bool(forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord) {
            pendingQuickRecord = true
            selectedTab = 0
        }
    }

    func markQuickRecordPending(clearingPreferences: Bool = false) {
        pendingQuickRecord = true
        selectedTab = 0
        let defaults = appGroupDefaults
        if clearingPreferences {
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
        }
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord)
        defaults.set(Date().timeIntervalSince1970, forKey: AppConstants.UserDefaultsKeys.quickRecordRequestedAt)
    }

    func clearQuickRecordFlag() {
        pendingQuickRecord = false
        let defaults = appGroupDefaults
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordRequestedAt)
    }

    func quickRecordPreferences() -> (language: AppLanguage?, outputType: OutputType?) {
        let defaults = appGroupDefaults
        let language = defaults.string(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
            .flatMap { AppLanguage(rawValue: $0) }
        let outputType = defaults.string(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
            .flatMap { OutputType(rawValue: $0) }
        return (language, outputType)
    }

    /// Extra settle time after a widget/Siri launch so the app is fully active before recording starts.
    func quickRecordLaunchDelay() -> TimeInterval {
        let requestedAt = appGroupDefaults.double(forKey: AppConstants.UserDefaultsKeys.quickRecordRequestedAt)
        guard requestedAt > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince1970 - requestedAt
        return max(0, 0.75 - elapsed)
    }

    private var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }
}
