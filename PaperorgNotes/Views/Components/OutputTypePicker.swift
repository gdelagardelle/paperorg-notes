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

struct LanguagePicker: View {
    @Binding var selection: AppLanguage
    
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
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
    }
}
