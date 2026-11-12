import SwiftUI

struct VyronWorkspaceTabItem: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    let tab: VyronWorkspaceTab
    var width = VyronWorkspaceTabsStyle.tabWidth

    var body: some View {
        HStack(spacing: VyronWorkspaceTabsStyle.compactSpacing) {
            Button { presentation.tabs.select(tab.id) } label: {
                HStack(spacing: VyronWorkspaceTabsStyle.spacing) {
                    Image(systemName: symbol)
                    Text(tab.title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, VyronWorkspaceTabsStyle.spacing)
                .frame(maxWidth: .infinity, minHeight: VyronWorkspaceTabsStyle.tabHeight)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if tab.id != presentation.tabs.conversationTabID {
                if isSelected {
                    closeButton.keyboardShortcut("w", modifiers: .command)
                } else {
                    closeButton
                }
            }
        }
        .font(VyronWorkspaceTabsStyle.titleFont)
        .buttonStyle(.plain)
        .frame(width: width, height: VyronWorkspaceTabsStyle.tabHeight)
        .background(isSelected ? Palette.field : Color.clear,
                    in: RoundedRectangle(cornerRadius: VyronWorkspaceTabsStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: VyronWorkspaceTabsStyle.radius)
            .stroke(isSelected ? Palette.border : Color.clear))
        .help(tab.title)
    }

    private var isSelected: Bool { presentation.tabs.selectedID == tab.id }

    private var closeButton: some View {
        Button { presentation.requestClose(tab.id) } label: {
            Image(systemName: VyronSymbols.browserCloseTab)
                .frame(width: VyronWorkspaceTabsStyle.controlSize, height: VyronWorkspaceTabsStyle.controlSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(VyronBrowserText.closeTab + ": " + tab.title)
        .help(VyronBrowserText.closeTab)
    }

    private var symbol: String {
        switch tab.location {
        case .conversation: VyronSymbols.chat
        case .home: VyronSymbols.browserGlobe
        case .website: VyronSymbols.browserGlobe
        case .page: VyronSymbols.newPage
        }
    }
}
