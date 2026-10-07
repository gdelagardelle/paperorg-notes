import Foundation

enum OfficeInboxError: LocalizedError {
    case missingToken
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "The office app token is missing on this Mac."
        case .badResponse(let message):
            return message
        }
    }
}

enum OfficeSpokenFields {
    struct Result: Equatable {
        var departement: String
        var statut: String
        /// Spoken file type the office task list has no column for.
        var fileLabel: String?
    }

    static func classify(_ text: String) -> Result {
        let folded = fold(text)
        let departement = department(in: folded)
        let label: String?
        if folded.contains("rabais") || folded.contains("remise") || folded.contains("ristourne") {
            label = "Rabais"
        } else if contains(folded, ["resiliation", "resilier", "resilieieren", "kundigung", "kuendigung", "opsoen"]) {
            label = "Résiliation"
        } else {
            label = nil
        }
        return Result(departement: departement, statut: status(in: folded), fileLabel: label)
    }

    static func clientName(project: String?, people: [String], assignee: String?) -> String? {
        let projectName = project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !projectName.isEmpty {
            return projectName
        }
        let assigneeFolded = fold(assignee ?? "")
        return people
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && fold($0) != assigneeFolded }
    }

    private static func department(in folded: String) -> String {
        if contains(folded, ["sinistre", "schaden", "schued"]) {
            return "Sinistre"
        }
        if contains(folded, ["contentieux", "litige"]) {
            return "Contentieux"
        }
        if contains(folded, ["resiliation", "resilier", "resilieieren", "kundigung", "kuendigung", "opsoen"]) {
            return "Contrat"
        }
        if contains(folded, ["rabais", "remise", "ristourne", "nachlass"]) {
            return "Commercial"
        }
        if contains(folded, ["contrat", "police", "vertrag"]) {
            return "Contrat"
        }
        return "Agence"
    }

    private static func status(in folded: String) -> String {
        if contains(folded, [
            "attente siege", "attente du siege", "attente compagnie", "en attente du siege",
            "waiting on the company", "waiting on the insurer", "waiting for the company",
            "waarde op d'compagnie", "waarde op de siege", "op de siege waarden",
            "warte op die gesellschaft", "beim versicherer"
        ]) {
            return "attente_siege"
        }
        if contains(folded, [
            "attente client", "attente du client", "en attente du client",
            "waiting on the client", "waiting for the client",
            "waarde op de client", "waarde op d'client",
            "ruckmeldung vom kunden", "warte auf den kunden"
        ]) {
            return "attente_client"
        }
        return "a_faire"
    }

    private static func contains(_ folded: String, _ needles: [String]) -> Bool {
        needles.contains { folded.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_LU"))
            .lowercased()
    }
}

enum OfficeInbox {
    static let endpoint = URL(string: "http://192.168.178.250:8000/api/paperorg/taches")!

    static func send(item: ActionItem, note: Note, keychain: KeychainService) async throws -> String {
        guard let token = keychain.retrieve(for: .officeInboxToken), !token.isEmpty else {
            throw OfficeInboxError.missingToken
        }
        return try await post(payload(item: item, note: note), token: token)
    }

    static func send(note: Note, assignee: String, keychain: KeychainService) async throws -> String {
        guard let token = keychain.retrieve(for: .officeInboxToken), !token.isEmpty else {
            throw OfficeInboxError.missingToken
        }
        let openItems = note.structuredOutput?.actionItems.filter { $0.status != .done && !$0.isCompleted } ?? []
        let title = openItems.first?.text ?? note.title
        let spoken = ([note.title, note.summaryShort ?? ""] + openItems.map(\.text)).joined(separator: "\n")
        let fields = OfficeSpokenFields.classify(spoken)
        var lines = [String]()
        if let label = fields.fileLabel {
            lines.append(label)
        }
        if let summary = note.summaryShort, !summary.isEmpty {
            lines.append(summary)
        }
        lines.append(contentsOf: openItems.map { "• \($0.text)" })
        var body: [String: Any] = [
            "titre": title,
            "description": lines.joined(separator: "\n\n"),
            "created_by": "Paperorg Notes",
            "priorite": "normale",
            "departement": fields.departement,
            "statut": fields.statut,
            "assignee_names": [assignee]
        ]
        if let client = OfficeSpokenFields.clientName(project: note.projectName, people: note.structuredOutput?.peopleMentioned ?? [], assignee: assignee) {
            body["client_nom"] = client
        }
        return try await post(body, token: token)
    }

    private static func payload(item: ActionItem, note: Note) -> [String: Any] {
        let spoken = [item.text, item.heardExcerpt ?? "", note.summaryShort ?? "", note.title].joined(separator: "\n")
        let fields = OfficeSpokenFields.classify(spoken)
        var lines = [String]()
        let sentence = item.heardExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sentence, !sentence.isEmpty {
            lines.append(sentence)
        } else {
            lines.append(item.text)
        }
        if let label = fields.fileLabel {
            lines.append(label)
        }
        if let summary = note.summaryShort, !summary.isEmpty {
            lines.append(summary)
        }
        lines.append("From: \(note.title)")
        if let sentBack = item.returnNote, !sentBack.isEmpty {
            lines.append("Sent back: \(sentBack)")
        }
        var body: [String: Any] = [
            "titre": item.text,
            "description": lines.joined(separator: "\n\n"),
            "created_by": "Paperorg Notes",
            "priorite": TaskDueDate.isTodayOrOverdue(item.dueAt) ? "haute" : "normale",
            "departement": fields.departement,
            "statut": fields.statut
        ]
        if let assignee = item.assignee, !assignee.isEmpty {
            body["assignee_names"] = [assignee]
        }
        if let due = item.dueAt {
            body["echeance"] = Self.dayStamp(due)
        }
        if let client = OfficeSpokenFields.clientName(
            project: note.projectName,
            people: note.structuredOutput?.peopleMentioned ?? [],
            assignee: item.assignee
        ) {
            body["client_nom"] = client
        }
        return body
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func post(_ body: [String: Any], token: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = json?["error"] as? String ?? "The office app returned \(status)."
            throw OfficeInboxError.badResponse(message)
        }
        if let reference = json?["reference"] as? String, !reference.isEmpty {
            return reference
        }
        if let id = json?["id"] as? Int {
            return "T-\(id)"
        }
        return "sent"
    }
}
