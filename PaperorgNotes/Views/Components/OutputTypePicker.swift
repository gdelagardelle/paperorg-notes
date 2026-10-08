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
        #if os(macOS)
        SelectionCard(caption: label) {
            Image(systemName: selection.icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } control: {
            Picker(label, selection: $selection) {
                ForEach(OutputType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .macSelectionPicker()
        }
        #else
        Menu {
            ForEach(OutputType.allCases) { type in
                Button {
                    selection = type
                } label: {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
        } label: {
            MenuCardLabel(
                caption: label,
                value: selection.displayName,
                icon: selection.icon
            )
        }
        #endif
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
        #if os(macOS)
        SelectionCard(caption: "Write the note in") {
            Image(systemName: "character.book.closed")
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } control: {
            Picker("Write the note in", selection: $selection) {
                ForEach(SummaryWriteLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .macSelectionPicker()
        }
        #else
        Menu {
            ForEach(SummaryWriteLanguage.allCases) { language in
                Button(language.title) {
                    selection = language
                }
            }
        } label: {
            MenuCardLabel(
                caption: "Write the note in",
                value: selection.title,
                icon: "character.book.closed"
            )
        }
        #endif
    }
}

struct LanguagePicker: View {
    @Binding var selection: AppLanguage

    /// Auto-detect is not a spoken choice, but a note can already be set to it.
    /// The menu has to contain that value or macOS draws an empty picker.
    private var choices: [AppLanguage] {
        if AppLanguage.spokenLanguages.contains(selection) {
            return AppLanguage.spokenLanguages
        }
        return [selection] + AppLanguage.spokenLanguages
    }
    
    var body: some View {
        #if os(macOS)
        SelectionCard(caption: "Language") {
            Text(selection.flag)
                .font(.title3)
                .frame(width: 28, height: 28)
        } control: {
            Picker("Language", selection: $selection) {
                ForEach(choices) { language in
                    Text("\(language.flag) \(language.displayName)").tag(language)
                }
            }
            .macSelectionPicker()
        }
        #else
        Menu {
            ForEach(choices) { language in
                Button("\(language.flag) \(language.displayName)") {
                    selection = language
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(selection.flag)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                    Text(selection.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .surfaceCard(padding: 14, cornerRadius: 16)
        }
        #endif
    }
}

#if !os(macOS)
private struct MenuCardLabel: View {
    let caption: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .surfaceCard(padding: 14, cornerRadius: 16)
    }
}
#endif

#if os(macOS)
/// macOS `Menu` labels collapse to a single clipped line. A menu-style
/// `Picker` keeps the selected value on the card.
private struct SelectionCard<Icon: View, Control: View>: View {
    let caption: String
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon()
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .surfaceCard(padding: 14, cornerRadius: 16)
    }
}

private extension View {
    func macSelectionPicker() -> some View {
        self
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
