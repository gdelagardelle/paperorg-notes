import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var filterLanguage: AppLanguage?
    @State private var filterProject: String?
    @State private var showFavoritesOnly = false
    
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
                if notes.isEmpty {
                    emptyLibraryView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            filterBar
                            
                            if filteredNotes.isEmpty {
                                noResultsView
                            } else {
                                LazyVStack(spacing: 10) {
                                    ForEach(filteredNotes) { note in
                                        NavigationLink(destination: NoteDetailView(note: note)) {
                                            NoteCardRow(note: note)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                try? environment.deleteNoteUseCase.deleteNote(note, context: modelContext)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(AppScreenBackground())
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
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppTheme.primary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var filterBar: some View {
        if showFavoritesOnly || filterLanguage != nil || filterProject != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Filters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if showFavoritesOnly {
                            FilterChip(title: "Favorites", isSelected: true) {
                                showFavoritesOnly = false
                            }
                        }
                        if let filterLanguage {
                            FilterChip(
                                title: "\(filterLanguage.flag) \(filterLanguage.displayName)",
                                isSelected: true
                            ) {
                                self.filterLanguage = nil
                            }
                        }
                        if let filterProject {
                            FilterChip(title: filterProject, isSelected: true) {
                                self.filterProject = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "doc.text")
        } description: {
            Text("Record something from the Record tab to build your library.")
        }
        .foregroundStyle(AppTheme.textSecondary)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            Text("No matching notes")
                .font(.headline)
            Text("Try clearing a filter or recording something new.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 32)
    }
}

struct NoteListRow: View {
    let note: Note
    
    var body: some View {
        NoteCardRow(note: note)
    }
}
