import Foundation

enum SummaryJSONParser {
    static func decode(_ data: Data) throws -> StructuredOutputDTO {
        let payload = try extractJSONObject(from: data)
        return StructuredOutputDTO(dictionary: payload)
    }

    static func decodeChatCompletionContent(_ data: Data) throws -> StructuredOutputDTO {
        if let response = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
           let content = response.choices.first?.message.content {
            return try decode(content.data(using: .utf8) ?? Data())
        }
        return try decode(data)
    }

    private static func extractJSONObject(from data: Data) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let nested = try nestedSummaryObject(in: object) {
            return nested
        }

        guard var text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw SummaryParseError.invalidResponse
        }

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let nested = try nestedSummaryObject(in: object) else {
            throw SummaryParseError.invalidResponse
        }
        return nested
    }

    private static func nestedSummaryObject(in object: [String: Any]) throws -> [String: Any]? {
        if hasSummaryFields(object) {
            return object
        }

        if let detail = object["detail"] as? String, !detail.isEmpty {
            throw SummaryParseError.serverError(detail)
        }

        if let choices = object["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String,
           let contentData = content.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
           hasSummaryFields(parsed) {
            return parsed
        }

        return nil
    }

    private static func hasSummaryFields(_ object: [String: Any]) -> Bool {
        ["shortSummary", "short_summary", "detailedSummary", "detailed_summary", "summary"]
            .contains { key in
                (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
    }
}

enum SummaryParseError: LocalizedError {
    case invalidResponse
    case emptySummary
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The summary service returned an unexpected response. Try again from the note."
        case .emptySummary:
            return "The summary came back empty. Try re-summarizing from the note."
        case .serverError(let message):
            return message
        }
    }
}

struct StructuredOutputDTO {
    var title: String?
    var shortSummary: String
    var detailedSummary: String
    var keyIdeas: [String]
    var decisions: [String]
    var actionItems: [ActionItemDTO]
    var openQuestions: [String]
    var risks: [String]
    var nextSteps: [String]
    var peopleMentioned: [String]
    var datesMentioned: [String]
    var importantNumbers: [String]
    var followUpEmailDraft: String?

    init(dictionary object: [String: Any]) {
        title = Self.string(from: object, keys: "title")
        shortSummary = Self.string(from: object, keys: "shortSummary", "short_summary", "summary") ?? ""
        detailedSummary = Self.string(
            from: object,
            keys: "detailedSummary", "detailed_summary", "long_summary", "summary_detailed"
        ) ?? shortSummary
        keyIdeas = Self.stringArray(from: object, keys: "keyIdeas", "key_ideas")
        decisions = Self.stringArray(from: object, keys: "decisions")
        actionItems = Self.actionItems(from: object)
        openQuestions = Self.stringArray(from: object, keys: "openQuestions", "open_questions")
        risks = Self.stringArray(from: object, keys: "risks")
        nextSteps = Self.stringArray(from: object, keys: "nextSteps", "next_steps")
        peopleMentioned = Self.stringArray(from: object, keys: "peopleMentioned", "people_mentioned")
        datesMentioned = Self.stringArray(from: object, keys: "datesMentioned", "dates_mentioned")
        importantNumbers = Self.stringArray(from: object, keys: "importantNumbers", "important_numbers")
        followUpEmailDraft = Self.string(from: object, keys: "followUpEmailDraft", "follow_up_email_draft")
    }

    func normalized() throws -> StructuredOutputDTO {
        let trimmedShort = shortSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetailed = detailedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShort.isEmpty || !trimmedDetailed.isEmpty else {
            throw SummaryParseError.emptySummary
        }
        var copy = self
        copy.shortSummary = trimmedShort.isEmpty ? trimmedDetailed : trimmedShort
        copy.detailedSummary = trimmedDetailed.isEmpty ? copy.shortSummary : trimmedDetailed
        return copy
    }

    private static func string(from object: [String: Any], keys: String...) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func stringArray(from object: [String: Any], keys: String...) -> [String] {
        for key in keys {
            if let values = object[key] as? [String] {
                return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            if let values = object[key] as? [Any] {
                return values.compactMap { $0 as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    private static func actionItems(from object: [String: Any]) -> [ActionItemDTO] {
        for key in ["actionItems", "action_items"] {
            guard let rawItems = object[key] as? [Any] else { continue }
            return rawItems.compactMap { item in
                if let text = item as? String, !text.isEmpty {
                    return ActionItemDTO(text: text, assignee: nil, dueDate: nil)
                }
                guard let dict = item as? [String: Any],
                      let text = string(from: dict, keys: "text", "task", "item"),
                      !text.isEmpty else {
                    return nil
                }
                return ActionItemDTO(
                    text: text,
                    assignee: string(from: dict, keys: "assignee", "owner"),
                    dueDate: string(from: dict, keys: "dueDate", "due_date", "due")
                )
            }
        }
        return []
    }
}

struct ActionItemDTO {
    let text: String
    let assignee: String?
    let dueDate: String?
}

private struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}

private struct OpenAIMessage: Decodable {
    let content: String
}
