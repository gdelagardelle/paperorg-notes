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
            triggerQuickRecord(clearingPreferences: true)
        default:
            break
        }
    }
    
    func consumeAppGroupQuickRecordFlag() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        if defaults.bool(forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord) {
            triggerQuickRecord()
        }
    }
    
    private func triggerQuickRecord(clearingPreferences: Bool = false) {
        pendingQuickRecord = true
        selectedTab = 0
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        if clearingPreferences {
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
            defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
        }
        defaults.set(true, forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord)
    }
    
    func clearQuickRecordFlag() {
        pendingQuickRecord = false
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.pendingQuickRecord)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
    }
    
    func quickRecordPreferences() -> (language: AppLanguage?, outputType: OutputType?) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
        let language = defaults.string(forKey: AppConstants.UserDefaultsKeys.quickRecordLanguage)
            .flatMap { AppLanguage(rawValue: $0) }
        let outputType = defaults.string(forKey: AppConstants.UserDefaultsKeys.quickRecordOutputType)
            .flatMap { OutputType(rawValue: $0) }
        return (language, outputType)
    }
}
