import Foundation

struct Teammate: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var email: String
    var nameRecordingFile: String?

    init(id: UUID = UUID(), name: String, email: String = "", nameRecordingFile: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.nameRecordingFile = nameRecordingFile
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasEmail: Bool {
        trimmedEmail.range(
            of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,
            options: .regularExpression
        ) != nil
    }

    /// First-run roster for a small office. Emails stay empty until filled in Settings.
    static let starterOffice: [Teammate] = [
        Teammate(name: "Dany"),
        Teammate(name: "Yannick"),
        Teammate(name: "Björn")
    ]
}
