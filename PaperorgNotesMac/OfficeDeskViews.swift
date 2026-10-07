import SwiftData
import SwiftUI

struct DecisionsBoardView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    private var rows: [(id: String, text: String, note: Note)] {
        notes.flatMap { note in
            (note.structuredOutput?.decisions ?? []).enumerated().map { index, text in
                (id: "\(note.id.uuidString)-\(index)", text: text, note: note)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Decisions")
                .font(.largeTitle.bold())
                .padding()
            if rows.isEmpty {
                ContentUnavailableView(
                    "No decisions yet",
                    systemImage: "checkmark.seal",
                    description: Text("Decisions extracted from recordings show up here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.text)
                        Text(row.note.title)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct ClientDossiersView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var selectedClient: String?

    private var clientNames: [String] {
        let fromNotes = notes.compactMap(\.projectName).filter { !$0.isEmpty }
        let fromFiles = environment.settingsService.clientFiles.map(\.name)
        return Array(Set(fromNotes + fromFiles)).sorted()
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedClient) {
                ForEach(clientNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(minWidth: 180, maxWidth: 240)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)

            if let selectedClient {
                dossier(for: selectedClient)
            } else {
                ContentUnavailableView(
                    "No client selected",
                    systemImage: "folder",
                    description: Text("Set a project on a note, or add a client in Settings.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func dossier(for name: String) -> some View {
        let related = notes.filter { $0.projectName?.caseInsensitiveCompare(name) == .orderedSame }
        let decisions = related.flatMap { $0.structuredOutput?.decisions ?? [] }
        let tasks = related.flatMap { note in
            (note.structuredOutput?.actionItems ?? []).filter { $0.status != .done }.map { (note, $0) }
        }
        let owner = environment.settingsService.owner(forProject: name) ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(name).font(.largeTitle.bold())
                if owner.isEmpty {
                    Text("No default owner. Set one in Settings → Clients.")
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text("Default owner: \(owner)")
                }
                if let draft = related.compactMap({ $0.structuredOutput?.followUpEmailDraft }).first(where: { !$0.isEmpty }),
                   !owner.isEmpty,
                   let person = environment.settingsService.teammate(named: owner),
                   person.hasEmail {
                    Button("Email follow-up to \(person.trimmedName)") {
                        if let url = TeamHandoff.mailURL(
                            to: person.trimmedEmail,
                            subject: "Follow-up: \(name)",
                            body: draft
                        ) {
                            openURL(url)
                        }
                    }
                }
                Text("Open tasks").font(.headline)
                if tasks.isEmpty {
                    Text("None").foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(tasks, id: \.1.id) { pair in
                        Text("• \(pair.1.text)")
                    }
                }
                Text("Decisions").font(.headline)
                if decisions.isEmpty {
                    Text("None").foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(decisions, id: \.self) { decision in
                        Text("• \(decision)")
                    }
                }
                Text("Notes").font(.headline)
                ForEach(related) { note in
                    Text(note.title)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
