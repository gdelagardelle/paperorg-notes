import Foundation

enum ActionItemPersistence {
    static func setCompleted(_ completed: Bool, itemId: UUID, on note: Note) {
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.isCompleted = completed
            copy.status = completed ? .done : (item.status == .done ? .open : item.status)
            return copy
        }
    }

    static func setStatus(_ status: TaskWorkflowStatus, itemId: UUID, on note: Note) {
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.status = status
            copy.isCompleted = status == .done
            return copy
        }
    }

    static func assign(_ assignee: String?, itemId: UUID, on note: Note) {
        let trimmed = assignee?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty == false) ? trimmed : nil
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.assignee = value
            return copy
        }
    }

    static func setDue(_ date: Date?, itemId: UUID, on note: Note) {
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.dueAt = date
            if let date {
                copy.dueDate = date.formatted(date: .abbreviated, time: .omitted)
            }
            return copy
        }
    }

    static func setReturnNote(_ noteText: String?, itemId: UUID, on note: Note) {
        let trimmed = noteText?.trimmingCharacters(in: .whitespacesAndNewlines)
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.returnNote = (trimmed?.isEmpty == false) ? trimmed : nil
            if copy.returnNote != nil, copy.status != .done {
                copy.status = .waiting
            }
            return copy
        }
    }

    static func markMailOpened(itemId: UUID, on note: Note) {
        update(itemId: itemId, on: note) { item in
            var copy = item
            copy.handoffMail = .mailOpened
            if copy.status == .open {
                copy.status = .handedOff
            }
            return copy
        }
    }

    static func assignOpenItems(to assignee: String, on note: Note) {
        guard let output = note.structuredOutput else { return }
        let updatedItems = output.actionItems.map { item -> ActionItem in
            guard !item.isCompleted else { return item }
            var copy = item
            copy.assignee = assignee
            return copy
        }
        write(updatedItems, on: note, output: output)
    }

    static func split(itemId: UUID, into parts: [String], on note: Note) {
        let cleaned = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard cleaned.count >= 2, let output = note.structuredOutput else { return }
        var items: [ActionItem] = []
        for item in output.actionItems {
            guard item.id == itemId else {
                items.append(item)
                continue
            }
            for part in cleaned {
                items.append(ActionItem(
                    text: part,
                    assignee: item.assignee,
                    dueDate: item.dueDate,
                    dueAt: item.dueAt,
                    status: item.status == .done ? .open : item.status,
                    handoffMail: .none,
                    heardExcerpt: item.heardExcerpt,
                    splitFrom: item.id
                ))
            }
        }
        write(items, on: note, output: output)
    }

    private static func update(itemId: UUID, on note: Note, transform: (ActionItem) -> ActionItem) {
        guard let output = note.structuredOutput else { return }
        let updatedItems = output.actionItems.map { item -> ActionItem in
            guard item.id == itemId else { return item }
            return transform(item)
        }
        write(updatedItems, on: note, output: output)
    }

    private static func write(_ items: [ActionItem], on note: Note, output: StructuredOutput) {
        note.structuredOutputJSON = try? JSONEncoder().encode(replacingItems(items, in: output))
    }

    private static func replacingItems(_ items: [ActionItem], in output: StructuredOutput) -> StructuredOutput {
        StructuredOutput(
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
}
