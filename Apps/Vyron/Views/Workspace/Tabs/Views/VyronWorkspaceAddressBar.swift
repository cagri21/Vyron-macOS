import AppKit
import SwiftUI

struct VyronWorkspaceAddressBar: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @State private var input = ""
    @FocusState private var isFocused: Bool
    let navigation: VyronWorkspaceNavigationContext
    let command: (VyronWorkspaceNavigationAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: VyronWorkspaceTabsStyle.spacing) {
                control(VyronBrowserText.back, symbol: VyronSymbols.browserBack, enabled: navigation.canGoBack) {
                    command(.back)
                }
                control(VyronBrowserText.forward, symbol: VyronSymbols.browserForward, enabled: navigation.canGoForward) {
                    command(.forward)
                }
                control(
                    navigation.isLoading ? VyronBrowserText.stop : VyronBrowserText.reload,
                    symbol: navigation.isLoading ? VyronSymbols.browserStop : VyronSymbols.browserReload,
                    enabled: !navigation.address.isEmpty
                ) {
                    command(navigation.isLoading ? .stop : .reload)
                }
                HStack(spacing: VyronWorkspaceTabsStyle.spacing) {
                    Button { isFocused = true } label: {
                        Image(systemName: navigation.address.hasPrefix("https://")
                              ? VyronSymbols.browserSecure : VyronSymbols.browserGlobe)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("l", modifiers: .command)
                    .accessibilityLabel(VyronBrowserText.addressPlaceholder)
                    TextField(VyronBrowserText.addressPlaceholder, text: $input)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            if presentation.submitAddress(input) { isFocused = false }
                        }
                        .accessibilityLabel(VyronBrowserText.addressPlaceholder)
                }
                .padding(.horizontal, VyronWorkspaceTabsStyle.padding)
                .frame(minWidth: VyronWorkspaceTabsStyle.minimumAddressWidth)
                .frame(height: VyronWorkspaceTabsStyle.controlSize)
                .background(Palette.field, in: Capsule())
                control(
                    VyronBrowserText.openExternal, symbol: VyronSymbols.browserExternal,
                    enabled: !navigation.address.isEmpty
                ) {
                    guard let url = URL(string: navigation.address),
                        VyronWorkspaceAddress.isAllowedWebsite(url)
                    else { return }
                    if !NSWorkspace.shared.open(url) { presentation.addressError = VyronToolsText.openFailed }
                }
            }
            .font(VyronWorkspaceTabsStyle.addressFont)
            .padding(.horizontal, VyronWorkspaceTabsStyle.padding)
            .frame(height: VyronWorkspaceTabsStyle.chromeHeight)
            if let error = presentation.addressError ?? presentation.tabs.errorMessage {
                Text(error)
                    .font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(Palette.muted)
                    .padding(.horizontal, VyronWorkspaceTabsStyle.padding)
                    .padding(.bottom, VyronWorkspaceTabsStyle.spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
        }
        .onAppear {
            input = navigation.address
            isFocused = presentation.tabs.selectedTab.kind == .home
        }
        .onChange(of: navigation.address) { _, address in
            if !isFocused { input = address }
        }
        .onChange(of: presentation.tabs.selectedID) { _, _ in
            input = navigation.address
            isFocused = presentation.tabs.selectedTab.kind == .home
        }
    }

    private func control(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: VyronWorkspaceTabsStyle.controlSize, height: VyronWorkspaceTabsStyle.controlSize)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : VyronWorkspaceTabsStyle.disabledOpacity)
        .help(title).accessibilityLabel(title)
    }
}
