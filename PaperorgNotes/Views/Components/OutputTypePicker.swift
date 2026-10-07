import SwiftUI

struct OutputTypePicker: View {
    @Binding var selection: OutputType
    var label: String = "Note style"
    var style: Style = .menu
    
    enum Style {
        case menu
        case chips
    }
    
    var body: some View {
        switch style {
        case .menu:
            menuPicker
        case .chips:
            chipsPicker
        }
    }
    
    private var menuPicker: some View {
        Menu {
            ForEach(OutputType.allCases) { type in
                Button {
                    selection = type
                } label: {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
        } label: {
            HStack {
                Image(systemName: selection.icon)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                    Text(selection.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .surfaceCard(padding: 14, cornerRadius: 16)
        }
        .macPickerMenu()
    }
    
    private var chipsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OutputType.allCases) { type in
                        SelectionChip(
                            title: type.displayName,
                            icon: type.icon,
                            isSelected: selection == type,
                            action: { selection = type }
                        )
                    }
                }
            }
        }
    }
}

struct SummaryWriteLanguagePicker: View {
    @Binding var selection: SummaryWriteLanguage

    var body: some View {
        Menu {
            ForEach(SummaryWriteLanguage.allCases) { language in
                Button(language.title) {
                    selection = language
                }
            }
        } label: {
            HStack {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Write the note in")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                    Text(selection.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .surfaceCard(padding: 14, cornerRadius: 16)
        }
        .macPickerMenu()
    }
}

struct LanguagePicker: View {
    @Binding var selection: AppLanguage
    
    var body: some View {
        Menu {
            ForEach(AppLanguage.spokenLanguages) { language in
                Button("\(language.flag) \(language.displayName)") {
                    selection = language
                }
            }
        } label: {
            HStack {
                Text(selection.flag)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                    Text(selection.displayName)
                        .font(.subheadline.bold())
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .surfaceCard(padding: 14, cornerRadius: 16)
        }
        .macPickerMenu()
    }
}

private extension View {
    /// macOS draws a Menu shorter than its label and adds a second chevron,
    /// so the next row paints on top of the first.
    @ViewBuilder
    func macPickerMenu() -> some View {
        #if os(macOS)
        self
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        #else
        self
        #endif
    }
}
