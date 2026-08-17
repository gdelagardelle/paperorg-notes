import UIKit

@MainActor
private final class BackgroundTaskHandle: @unchecked Sendable {
    private let application: UIApplication
    var identifier = UIBackgroundTaskIdentifier.invalid

    init(application: UIApplication) {
        self.application = application
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// Keeps async work alive briefly when the user locks the phone mid-stop or mid-processing.
enum BackgroundTaskRunner {
    @MainActor
    static func run<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let application = UIApplication.shared
        let handle = BackgroundTaskHandle(application: application)
        handle.identifier = application.beginBackgroundTask(withName: name) {
            Task { @MainActor in
                handle.end()
            }
        }
        defer {
            handle.end()
        }
        return try await operation()
    }
}
