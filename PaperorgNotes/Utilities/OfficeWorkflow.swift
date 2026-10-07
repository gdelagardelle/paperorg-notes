import Foundation

enum OfficeWorkflow {
    static func enrich(
        _ output: StructuredOutput,
        transcript: String,
        segments: [TranscriptSegmentModel],
        teammates: [Teammate],
        defaultOwner: String?
    ) -> StructuredOutput {
        let roster = teammates.filter { !$0.trimmedName.isEmpty }
        let spokenAssignee = assigneeSpoken(in: transcript, roster: roster)
        let items = output.actionItems.map { item -> ActionItem in
            var copy = item
            if copy.dueAt == nil {
                copy.dueAt = TaskDueDate.parse(copy.dueDate)
            }
            if let matched = match(copy.assignee, roster: roster) {
                copy.assignee = matched.trimmedName
            } else if let mentioned = roster.first(where: { name in
                containsName(name.trimmedName, in: copy.text)
            }) {
                copy.assignee = mentioned.trimmedName
            } else if copy.assignee == nil, let spokenAssignee {
                copy.assignee = spokenAssignee.trimmedName
            } else if copy.assignee == nil,
                      let owner = defaultOwner?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !owner.isEmpty {
                copy.assignee = owner
            }
            if copy.heardExcerpt == nil {
                copy.heardExcerpt = excerpt(for: copy.text, segments: segments, transcript: transcript)
            }
            return copy
        }
        return StructuredOutput(
            outputType: output.outputType,
            title: output.title,
            shortSummary: output.shortSummary,
            detailedSummary: output.detailedSummary,
            keyIdeas: output.keyIdeas,
            decisions: output.decisions,
            actionItems: items,
            openQuestions: output.openQuestions,
            risks: output.risks,
            nextSteps: output.nextSteps,
            peopleMentioned: output.peopleMentioned,
            datesMentioned: output.datesMentioned,
            importantNumbers: output.importantNumbers,
            followUpEmailDraft: output.followUpEmailDraft,
            generatedAt: output.generatedAt
        )
    }

    static func digestBody(notes: [Note], teammates: [Teammate]) -> String {
        var lines = ["Open tasks", ""]
        let people = teammates.map(\.trimmedName).filter { !$0.isEmpty }
        var claimed = Set<UUID>()
        for name in people {
            let tasks = openTasks(in: notes).filter { $0.item.assignee?.caseInsensitiveCompare(name) == .orderedSame }
            guard !tasks.isEmpty else { continue }
            lines.append(name)
            for row in tasks {
                claimed.insert(row.item.id)
                lines.append("• \(line(for: row))")
            }
            lines.append("")
        }
        let rest = openTasks(in: notes).filter { !claimed.contains($0.item.id) }
        if !rest.isEmpty {
            lines.append("Unassigned")
            for row in rest {
                lines.append("• \(line(for: row))")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func openTasks(in notes: [Note]) -> [(item: ActionItem, note: Note)] {
        notes.flatMap { note in
            (note.structuredOutput?.actionItems ?? [])
                .filter { $0.status != .done && !$0.isCompleted }
                .map { ($0, note) }
        }
    }

    private static func line(for row: (item: ActionItem, note: Note)) -> String {
        var text = row.item.text
        if let due = row.item.dueAt {
            text += " (due \(due.formatted(date: .abbreviated, time: .omitted)))"
        } else if let due = row.item.dueDate, !due.isEmpty {
            text += " (due \(due))"
        }
        text += " — \(row.note.title)"
        return text
    }

    private static func match(_ raw: String?, roster: [Teammate]) -> Teammate? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return roster.first { teammate in
            containsName(teammate.trimmedName, in: trimmed) || containsName(trimmed, in: teammate.trimmedName)
        }
    }

    private static func assigneeSpoken(in transcript: String, roster: [Teammate]) -> Teammate? {
        let patterns = ["give this to ", "give it to ", "for ", "pour ", "fir ", "un ", "fir den ", "fir d'"]
        let lower = transcript.lowercased()
        for person in roster {
            let name = person.trimmedName.lowercased()
            for pattern in patterns where lower.contains(pattern + name) {
                return person
            }
        }
        return nil
    }

    private static func containsName(_ name: String, in text: String) -> Bool {
        let name = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let text = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        guard !name.isEmpty else { return false }
        return text.contains(name)
    }

    private static func excerpt(for task: String, segments: [TranscriptSegmentModel], transcript: String) -> String? {
        let needle = task
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 4 }
            .first?
            .lowercased()
        if let needle, let segment = segments.first(where: { $0.text.lowercased().contains(needle) }) {
            return segment.text
        }
        if let needle, let range = transcript.lowercased().range(of: needle) {
            let start = transcript.index(range.lowerBound, offsetBy: -40, limitedBy: transcript.startIndex) ?? transcript.startIndex
            let end = transcript.index(range.upperBound, offsetBy: 80, limitedBy: transcript.endIndex) ?? transcript.endIndex
            return String(transcript[start..<end])
        }
        return nil
    }
}
