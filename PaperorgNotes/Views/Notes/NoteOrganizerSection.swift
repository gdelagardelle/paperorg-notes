import SwiftUI

struct NoteOrganizerSection: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @State private var newTag = ""
    @State private var projectName: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organize")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("Client, team, folder…", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveProject() }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(note.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button {
                                note.tags.removeAll { $0 == tag }
                                save()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.primary.opacity(0.12))
                        .foregroundStyle(AppTheme.primary)
                        .clipShape(Capsule())
                    }
                }
                
                HStack {
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addTag() }
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .cardStyle()
        .onAppear {
            projectName = note.projectName ?? ""
        }
        .onChange(of: projectName) { _, _ in
            saveProject()
        }
    }
    
    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !note.tags.contains(tag) else { return }
        note.tags.append(tag)
        newTag = ""
        save()
    }
    
    private func saveProject() {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        note.projectName = trimmed.isEmpty ? nil : trimmed
        save()
    }
    
    private func save() {
        note.updatedAt = .now
        try? modelContext.save()
    }
}

/// Simple horizontal flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
