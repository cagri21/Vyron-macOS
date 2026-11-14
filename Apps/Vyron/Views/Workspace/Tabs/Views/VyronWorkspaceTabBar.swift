import SwiftUI

struct VyronWorkspaceTabBar: View {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation

    var body: some View {
        GeometryReader { geometry in
            let count = presentation.tabs.tabs.count
            let width = VyronWorkspaceTabsStyle.tabItemWidth(containerWidth: geometry.size.width, count: count)
            let available = geometry.size.width - VyronWorkspaceTabsStyle.controlSize
                - VyronWorkspaceTabsStyle.spacing - VyronWorkspaceTabsStyle.compactSpacing * 2
            let minimumContentWidth = CGFloat(count) * VyronWorkspaceTabsStyle.minimumTabWidth
                + CGFloat(count - 1) * VyronWorkspaceTabsStyle.compactSpacing
            HStack(spacing: VyronWorkspaceTabsStyle.compactSpacing) {
                Group {
                    if minimumContentWidth <= available {
                        strip(width: width).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) { strip(width: width) }
                                .scrollIndicators(.hidden)
                                .onChange(of: presentation.tabs.selectedID) { _, id in
                                    proxy.scrollTo(id, anchor: .trailing)
                                }
                        }
                    }
                }
                .padding(.leading, VyronWorkspaceTabsStyle.compactSpacing)
                Button { presentation.newTab() } label: {
                    Image(systemName: VyronSymbols.browserNewTab)
                        .frame(width: VyronWorkspaceTabsStyle.controlSize, height: VyronWorkspaceTabsStyle.controlSize)
                }
                .buttonStyle(.plain)
                .help(VyronBrowserText.newTab)
                .accessibilityLabel(VyronBrowserText.newTab)
            }
            .padding(.trailing, VyronWorkspaceTabsStyle.spacing)
            .frame(height: VyronWorkspaceTabsStyle.tabBarHeight)
        }
        .frame(height: VyronWorkspaceTabsStyle.tabBarHeight)
        .background(palette.sidebar)
    }

    private func strip(width: CGFloat) -> some View {
        HStack(spacing: VyronWorkspaceTabsStyle.compactSpacing) {
            ForEach(presentation.tabs.tabs) { tab in
                VyronWorkspaceTabItem(tab: tab, width: width).id(tab.id)
            }
        }
    }
}
