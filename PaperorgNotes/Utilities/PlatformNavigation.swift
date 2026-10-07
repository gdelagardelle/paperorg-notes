import SwiftUI

enum PlatformToolbar {
    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

extension View {
    @ViewBuilder
    func platformNoAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformEmailKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformEmailKeyboardType() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformAutocorrectionDisabled() -> some View {
        #if os(iOS)
        autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformHiddenNavigationBar() -> some View {
        #if os(iOS)
        navigationBarHidden(true)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformInsetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    func platformHiddenScrollContentBackground() -> some View {
        #if os(iOS)
        scrollContentBackground(.hidden)
        #else
        self
        #endif
    }
}
