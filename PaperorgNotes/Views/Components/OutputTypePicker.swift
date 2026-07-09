import SwiftUI

struct OutputTypePicker: View {
    @Binding var selection: OutputType
    var label: String = "Note style"
    
    var body: some View {
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
                    .foregroundStyle(AppTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(selection.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(selection.displayName)
                        .font(.subheadline.bold())
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
