import SwiftUI

struct VyronWorkspaceNavigationControls: View {
    @Environment(\.locale) private var localizationLocale
    @Binding var showSidebar: Bool

    var body: some View {
        let _ = localizationLocale
        Button { showSidebar.toggle() } label: {
            VyronWorkspaceHeaderIcon(symbol: VyronSymbols.sidebarLeft)
        }
        .buttonStyle(.plain)
        .help(showSidebar ? VyronWorkspaceText.hideSidebar : VyronWorkspaceText.showSidebar)
        .accessibilityLabel(showSidebar ? VyronWorkspaceText.hideSidebar : VyronWorkspaceText.showSidebar)
    }
}
