import Foundation

/// Build-time backend URLs from Info.plist (set via XcodeGen configs).
enum BackendConfiguration {
    static var defaultProBackendURL: String {
        string(for: "PAPERORG_PRO_BACKEND_URL") ?? "http://127.0.0.1:8080"
    }

    static var defaultPlatformAPIURL: String {
        string(for: "PAPERORG_PLATFORM_API_URL") ?? "http://127.0.0.1:8000"
    }

    static var usePlatformAuthByDefault: Bool {
        string(for: "PAPERORG_USE_PLATFORM_AUTH") == "YES"
    }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
