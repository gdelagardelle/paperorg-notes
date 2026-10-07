import Foundation

struct ClientFile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var defaultOwner: String

    init(id: UUID = UUID(), name: String, defaultOwner: String = "") {
        self.id = id
        self.name = name
        self.defaultOwner = defaultOwner
    }
}

struct StandingMeeting: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var outputTypeRaw: String
    var tags: [String]
    var assigneeNames: [String]

    init(
        id: UUID = UUID(),
        title: String,
        outputType: OutputType = .meetingNotes,
        tags: [String] = [],
        assigneeNames: [String] = []
    ) {
        self.id = id
        self.title = title
        self.outputTypeRaw = outputType.rawValue
        self.tags = tags
        self.assigneeNames = assigneeNames
    }

    var outputType: OutputType {
        OutputType(rawValue: outputTypeRaw) ?? .meetingNotes
    }
}
