import SwiftUI
import SwiftData

struct NotesListView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var filterLanguage: AppLanguage?
    @State private var showFavoritesOnly = false
    
    var filteredNotes: [Note] {
        notes.filter { note in
            if showFavoritesOnly && !note.isFavorite { return false }
            if let lang = filterLanguage, note.language != lang.rawValue { return false }
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
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            
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
