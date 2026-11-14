import SwiftUI

struct VyronWorkspaceNavigationControls: View {
    @Environment(\.locale) private var localizationLocale
    let isSidebarPresented: Bool
    let toggleSidebar: () -> Void

    var body: some View {
        let _ = localizationLocale
        Button(action: toggleSidebar) {
            VyronWorkspaceHeaderIcon(symbol: VyronSymbols.sidebarLeft)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("b", modifiers: .command)
        .help(isSidebarPresented ? VyronWorkspaceText.hideSidebar : VyronWorkspaceText.showSidebar)
        .accessibilityLabel(isSidebarPresented ? VyronWorkspaceText.hideSidebar : VyronWorkspaceText.showSidebar)
    }
}
