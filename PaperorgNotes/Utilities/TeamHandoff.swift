import Foundation

enum TeamHandoff {
    static func subject(note: Note, item: ActionItem?) -> String {
        if let item {
            return "Task: \(item.text)"
        }
        return "Note: \(note.title)"
    }

    static func body(note: Note, item: ActionItem?, recipientName: String) -> String {
        var lines: [String] = []
        lines.append("Hi \(recipientName),")
        lines.append("")
        if let item {
            lines.append("This task was handed to you from Paperorg Notes.")
            lines.append("")
            lines.append(item.text)
            if let due = item.dueDate, !due.isEmpty {
                lines.append("Due: \(due)")
            }
            lines.append("From: \(note.title)")
        } else {
            lines.append("This note was handed to you from Paperorg Notes.")
            lines.append("")
            lines.append(note.title)
        }

        if let excerpt = item?.heardExcerpt, !excerpt.isEmpty {
            lines.append("")
            lines.append("Heard: \(excerpt)")
        }

        if let summary = note.summaryShort, !summary.isEmpty {
            lines.append("")
            lines.append(summary)
        }

        if item == nil, let items = note.structuredOutput?.actionItems, !items.isEmpty {
            lines.append("")
            lines.append("Open tasks:")
            for task in items where !task.isCompleted {
                lines.append("• \(task.text)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func mailURL(to email: String, subject: String, body: String) -> URL? {
        guard var components = URLComponents(string: "mailto:\(email)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
