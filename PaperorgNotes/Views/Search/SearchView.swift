import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var query = ""
    @State private var filterLanguage: AppLanguage?
    @State private var filterTag = ""
    @State private var filterProject: String?
    
    private var projectNames: [String] {
        Array(Set(notes.compactMap(\.projectName).filter { !$0.isEmpty })).sorted()
    }
    
    var results: [Note] {
        notes.filter { note in
            if let lang = filterLanguage, note.language != lang.rawValue { return false }
            if let project = filterProject, note.projectName != project { return false }
            if !filterTag.isEmpty && !note.tags.contains(where: { $0.localizedCaseInsensitiveContains(filterTag) }) {
                return false
            }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return note.title.lowercased().contains(q)
                || (note.projectName?.lowercased().contains(q) ?? false)
                || (note.rawTranscript?.lowercased().contains(q) ?? false)
                || (note.correctedTranscript?.lowercased().contains(q) ?? false)
                || (note.summaryShort?.lowercased().contains(q) ?? false)
                || note.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                filterBar
                
                if query.isEmpty && filterLanguage == nil && filterTag.isEmpty && filterProject == nil {
                    ContentUnavailableView(
                        "Search Transcripts",
                        systemImage: "magnifyingglass",
                        description: Text("Find notes by keyword, language, or tag.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            SearchResultRow(note: note, query: query)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Search")
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
            TextField("Search transcripts…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }
    
    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppLanguage.allCases) { lang in
                        FilterChip(
                            title: "\(lang.flag) \(lang.displayName)",
                            isSelected: filterLanguage == lang
                        ) {
                            filterLanguage = filterLanguage == lang ? nil : lang
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(projectNames, id: \.self) { project in
                        FilterChip(
                            title: project,
                            isSelected: filterProject == project
                        ) {
                            filterProject = filterProject == project ? nil : project
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            HStack {
                TextField("Filter by tag", text: $filterTag)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
}

struct SearchResultRow: View {
    let note: Note
    let query: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.headline)
            
            if let snippet = matchingSnippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }
    
    private var matchingSnippet: String? {
        let text = note.displayTranscript
        guard !query.isEmpty, let range = text.range(of: query, options: .caseInsensitive) else {
            return note.summaryShort
        }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return "…" + text[start..<end] + "…"
    }
    
    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: note.createdAt)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppTheme.primary : AppTheme.surface)
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .clipShape(Capsule())
        }
    }
}
