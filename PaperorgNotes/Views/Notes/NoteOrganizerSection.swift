import SwiftUI

struct NoteOrganizerSection: View {
    @Bindable var note: Note
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @State private var newTag = ""
    @State private var projectName: String = ""
    @State private var handoffMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: "Organize", subtitle: "Project and tags for this note")

            VStack(alignment: .leading, spacing: 6) {
                Text("Project")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                TextField("Client, team, folder…", text: $projectName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    .onSubmit { saveProject() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)

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
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.primarySoft)
                        .foregroundStyle(AppTheme.primary)
                        .clipShape(Capsule())
                    }
                }

                HStack(spacing: 10) {
                    TextField("Add tag", text: $newTag)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                    Button("Add") { addTag() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.primarySoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !teammates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hand off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                    Text("Assign the open tasks on this note and open Mail.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Menu("Hand to…") {
                        ForEach(teammates) { person in
                            Button(person.trimmedName) { handOff(to: person) }
                        }
                    }
                    if let handoffMessage {
                        Text(handoffMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .surfaceCard()
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

    private var teammates: [Teammate] {
        environment.settingsService.teammates.filter { !$0.trimmedName.isEmpty }
    }

    private func handOff(to person: Teammate) {
        ActionItemPersistence.assignOpenItems(to: person.trimmedName, on: note)
        save()
        Task {
            do {
                let reference = try await OfficeInbox.send(
                    note: note,
                    assignee: person.trimmedName,
                    keychain: environment.keychainService
                )
                handoffMessage = "Assigned to \(person.trimmedName). Office task \(reference)."
            } catch {
                handoffMessage = "Assigned to \(person.trimmedName). \(error.localizedDescription)"
            }
        }
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
