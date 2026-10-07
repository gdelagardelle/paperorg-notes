import SwiftData
import SwiftUI

struct TaskInboxRow: Identifiable {
    let id: UUID
    let item: ActionItem
    let note: Note
}

struct TasksInboxView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var filter: TaskFilter = .open
    @State private var personFilter: String = "Everyone"
    @State private var handoffMessage: String?
    @State private var splitting: TaskInboxRow?
    @State private var splitA = ""
    @State private var splitB = ""

    enum TaskFilter: String, CaseIterable, Identifiable {
        case today
        case mine
        case open
        case handedOff
        case unassigned
        case waiting
        case done
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .mine: "Mine"
            case .open: "Open"
            case .handedOff: "Handed off"
            case .unassigned: "Unassigned"
            case .waiting: "Waiting"
            case .done: "Done"
            case .all: "All"
            }
        }
    }

    private var teammates: [Teammate] {
        environment.settingsService.teammates.filter { !$0.trimmedName.isEmpty }
    }

    private var rows: [TaskInboxRow] {
        notes.flatMap { note -> [TaskInboxRow] in
            guard let items = note.structuredOutput?.actionItems, !items.isEmpty else { return [] }
            return items.map { TaskInboxRow(id: $0.id, item: $0, note: note) }
        }
        .filter { row in
            let mine = environment.settingsService.deskUserName
            switch filter {
            case .today:
                return row.item.status != .done && TaskDueDate.isTodayOrOverdue(row.item.dueAt)
            case .mine:
                guard !mine.isEmpty else { return row.item.assignee == nil && row.item.status != .done }
                return row.item.assignee?.caseInsensitiveCompare(mine) == .orderedSame && row.item.status != .done
            case .open:
                return row.item.status == .open
            case .handedOff:
                return row.item.status == .handedOff || row.item.handoffMail == .mailOpened
            case .unassigned:
                return row.item.assignee?.isEmpty ?? true
            case .waiting:
                return row.item.status == .waiting
            case .done:
                return row.item.status == .done || row.item.isCompleted
            case .all:
                return true
            }
        }
        .filter { row in
            switch personFilter {
            case "Everyone":
                return true
            case "Unassigned":
                return row.item.assignee?.isEmpty ?? true
            default:
                return row.item.assignee?.caseInsensitiveCompare(personFilter) == .orderedSame
            }
        }
        .sorted { lhs, rhs in
            if lhs.item.isCompleted != rhs.item.isCompleted {
                return !lhs.item.isCompleted
            }
            return lhs.note.createdAt > rhs.note.createdAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tasks")
                    .font(.largeTitle.bold())
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .frame(maxWidth: 160)
                Button("Monday digest") { sendDigest() }
                Picker("Person", selection: $personFilter) {
                    Text("Everyone").tag("Everyone")
                    Text("Unassigned").tag("Unassigned")
                    ForEach(teammates) { person in
                        Text(person.trimmedName).tag(person.trimmedName)
                    }
                }
                .frame(maxWidth: 180)
            }
            .padding()

            if let handoffMessage {
                Text(handoffMessage)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal)
            }

            if rows.isEmpty {
                ContentUnavailableView(
                    "No tasks yet",
                    systemImage: "checklist",
                    description: Text("Record a voice note with task list output — action items appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    TaskInboxRowView(
                        row: row,
                        teammates: teammates,
                        onToggle: { toggle(row, completed: $0) },
                        onAssign: { assign(row, to: $0) },
                        onStatus: { setStatus(row, $0) },
                        onDue: { setDue(row, $0) },
                        onHandOff: { handOff(row) },
                        onSplit: { beginSplit(row) },
                        onReturn: { setReturn(row, $0) }
                    )
                }
            }
        }
        .sheet(item: $splitting) { row in
            VStack(alignment: .leading, spacing: 12) {
                Text("Split task")
                    .font(.title2.bold())
                Text(row.item.text)
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("First part", text: $splitA)
                TextField("Second part", text: $splitB)
                HStack {
                    Button("Cancel") { splitting = nil }
                    Button("Split") {
                        ActionItemPersistence.split(itemId: row.item.id, into: [splitA, splitB], on: row.note)
                        row.note.updatedAt = .now
                        try? modelContext.save()
                        splitting = nil
                    }
                    .disabled(splitA.trimmingCharacters(in: .whitespaces).isEmpty || splitB.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func toggle(_ row: TaskInboxRow, completed: Bool) {
        ActionItemPersistence.setCompleted(completed, itemId: row.item.id, on: row.note)
        row.note.updatedAt = .now
        try? modelContext.save()
    }

    private func assign(_ row: TaskInboxRow, to name: String?) {
        ActionItemPersistence.assign(name, itemId: row.item.id, on: row.note)
        row.note.updatedAt = .now
        try? modelContext.save()
        handoffMessage = nil
    }

    private func handOff(_ row: TaskInboxRow) {
        guard let name = row.item.assignee, !name.isEmpty else {
            handoffMessage = "Assign the task to someone on the team first."
            return
        }
        Task {
            do {
                let reference = try await OfficeInbox.send(
                    item: row.item,
                    note: row.note,
                    keychain: environment.keychainService
                )
                ActionItemPersistence.markMailOpened(itemId: row.item.id, on: row.note)
                row.note.updatedAt = .now
                try? modelContext.save()
                handoffMessage = "Sent to the office app as \(reference) for \(name)."
            } catch {
                handoffMessage = error.localizedDescription
            }
        }
    }

    private func setStatus(_ row: TaskInboxRow, _ status: TaskWorkflowStatus) {
        ActionItemPersistence.setStatus(status, itemId: row.item.id, on: row.note)
        row.note.updatedAt = .now
        try? modelContext.save()
    }

    private func setDue(_ row: TaskInboxRow, _ date: Date?) {
        ActionItemPersistence.setDue(date, itemId: row.item.id, on: row.note)
        row.note.updatedAt = .now
        try? modelContext.save()
    }

    private func setReturn(_ row: TaskInboxRow, _ text: String) {
        ActionItemPersistence.setReturnNote(text, itemId: row.item.id, on: row.note)
        row.note.updatedAt = .now
        try? modelContext.save()
        handoffMessage = "Sent back. It now waits on you."
    }

    private func beginSplit(_ row: TaskInboxRow) {
        splitA = row.item.text
        splitB = ""
        splitting = row
    }

    private func sendDigest() {
        let body = OfficeWorkflow.digestBody(notes: notes, teammates: teammates)
        let recipients = teammates.filter(\.hasEmail).map(\.trimmedEmail)
        guard !recipients.isEmpty,
              let url = TeamHandoff.mailURL(to: recipients.joined(separator: ","), subject: "Open tasks", body: body) else {
            handoffMessage = "Add at least one teammate email in Settings → Team."
            return
        }
        openURL(url)
        handoffMessage = "Monday digest opened in Mail."
    }
}

struct TaskInboxRowView: View {
    let row: TaskInboxRow
    let teammates: [Teammate]
    let onToggle: (Bool) -> Void
    let onAssign: (String?) -> Void
    let onStatus: (TaskWorkflowStatus) -> Void
    let onDue: (Date?) -> Void
    let onHandOff: () -> Void
    let onSplit: () -> Void
    let onReturn: (String) -> Void
    @State private var returnDraft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { row.item.isCompleted },
                set: { onToggle($0) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(row.item.text)
                    .strikethrough(row.item.isCompleted)
                    .foregroundStyle(row.item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)

                HStack(spacing: 8) {
                    Text(row.note.title)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if !row.note.tags.isEmpty {
                        Text("· \(row.note.tags.prefix(2).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    if let due = row.item.dueDate, !due.isEmpty {
                        Text("· \(due)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                HStack(spacing: 8) {
                    Menu(row.item.assignee ?? "Assign") {
                        Button("Unassigned") { onAssign(nil) }
                        ForEach(teammates) { person in
                            Button(person.trimmedName) { onAssign(person.trimmedName) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Menu(row.item.status.title) {
                        ForEach(TaskWorkflowStatus.allCases, id: \.self) { status in
                            Button(status.title) { onStatus(status) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    DatePicker(
                        "Due",
                        selection: Binding(
                            get: { row.item.dueAt ?? .now },
                            set: { onDue($0) }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(maxWidth: 140)

                    if row.item.handoffMail == .mailOpened {
                        Text("Mail opened")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }

                    Button("Hand off") { onHandOff() }
                        .buttonStyle(.borderless)
                        .disabled(row.item.assignee == nil)
                    Button("Split") { onSplit() }
                        .buttonStyle(.borderless)
                }

                if let excerpt = row.item.heardExcerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                if let sentBack = row.item.returnNote, !sentBack.isEmpty {
                    Text("Sent back: \(sentBack)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
                HStack {
                    TextField("Send back a note", text: $returnDraft)
                    Button("Send back") { onReturn(returnDraft) }
                        .disabled(returnDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
