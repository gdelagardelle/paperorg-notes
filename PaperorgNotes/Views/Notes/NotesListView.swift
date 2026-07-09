import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var filterLanguage: AppLanguage?
    @State private var filterProject: String?
    @State private var showFavoritesOnly = false
    @State private var notePendingDelete: Note?
    
    private var projectNames: [String] {
        Array(Set(notes.compactMap(\.projectName).filter { !$0.isEmpty })).sorted()
    }
    
    var filteredNotes: [Note] {
        notes.filter { note in
            if showFavoritesOnly && !note.isFavorite { return false }
            if let lang = filterLanguage, note.language != lang.rawValue { return false }
            if let project = filterProject, note.projectName != project { return false }
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredNotes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "doc.text",
                        description: Text("Record something to get started.")
                    )
                } else {
                    List(filteredNotes) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            NoteListRow(note: note)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                notePendingDelete = note
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Favorites Only", isOn: $showFavoritesOnly)
                        Divider()
                        Button("All Projects") { filterProject = nil }
                        ForEach(projectNames, id: \.self) { project in
                            Button(project) { filterProject = project }
                        }
                        Divider()
                        Button("All Languages") { filterLanguage = nil }
                        ForEach(AppLanguage.allCases) { lang in
                            Button("\(lang.flag) \(lang.displayName)") {
                                filterLanguage = lang
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .alert("Delete Note?", isPresented: Binding(
                get: { notePendingDelete != nil },
                set: { if !$0 { notePendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let note = notePendingDelete {
                        environment.deleteNoteUseCase.deleteNote(note, context: modelContext)
                    }
                    notePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    notePendingDelete = nil
                }
            } message: {
                Text("Permanently deletes this note, transcript, summary, and recording.")
            }
        }
    }
}

struct NoteListRow: View {
    let note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            }
            
            HStack(spacing: 8) {
                Text(note.appLanguage.flag)
                Text(formattedDate)
                Text(DurationFormatter.format(note.durationSeconds))
                if let project = note.projectName, !project.isEmpty {
                    Text(project)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            
            if !note.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }
                }
            }
            
            if let summary = note.summaryShort, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: note.createdAt)
    }
}
