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
            ScrollView {
                VStack(spacing: 16) {
                    searchBar
                    filterBar
                    
                    if query.isEmpty && filterLanguage == nil && filterTag.isEmpty && filterProject == nil {
                        searchPrompt
                    } else if results.isEmpty {
                        noResultsPrompt
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(results) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    SearchResultRow(note: note, query: query)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(AppScreenBackground())
            .navigationTitle("Search")
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
    
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refine")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            
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
            }
            
            if !projectNames.isEmpty {
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
                }
            }
            
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("Filter by tag", text: $filterTag)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
        .surfaceCard(padding: 16, cornerRadius: 18)
    }
    
    private var searchPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.accent.opacity(0.75))
            Text("Search your library")
                .font(.headline)
            Text("Find notes by keyword, language, project, or tag.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 36)
    }
    
    private var noResultsPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            Text("No results")
                .font(.headline)
            Text("Try a different keyword or clear your filters.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 32)
    }
}

struct SearchResultRow: View {
    let note: Note
    let query: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                NoteStatusBadge(status: note.noteStatus, compact: true)
            }
            
            if let snippet = matchingSnippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)
            }
            
            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .surfaceCard(padding: 16)
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
