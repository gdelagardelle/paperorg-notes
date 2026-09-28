import Foundation

/// A language boundary captured during recording (start time in seconds).
struct RecordingLanguageSegment: Codable, Sendable, Hashable {
    let languageCode: String
    let startTime: TimeInterval
}
