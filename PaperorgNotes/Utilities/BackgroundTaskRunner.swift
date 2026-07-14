import UIKit

/// Keeps async work alive briefly when the user locks the phone mid-stop or mid-processing.
enum BackgroundTaskRunner {
    static func run<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        let application = UIApplication.shared
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = application.beginBackgroundTask(withName: name) {
            application.endBackgroundTask(taskID)
        }
        defer {
            if taskID != .invalid {
                application.endBackgroundTask(taskID)
            }
        }
        return try await operation()
    }
}
