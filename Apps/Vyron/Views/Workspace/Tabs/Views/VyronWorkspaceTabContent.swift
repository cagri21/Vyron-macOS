import SwiftUI

struct VyronWorkspaceTabContent<ConversationContent: View>: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @ViewBuilder let conversation: () -> ConversationContent

    var body: some View {
        let selected = presentation.tabs.selectedTab
        ZStack {
            conversation()
                .opacity(selected.kind == .conversation ? 1 : 0)
                .allowsHitTesting(selected.kind == .conversation)
                .disabled(selected.kind != .conversation)
                .accessibilityHidden(selected.kind != .conversation)
            ForEach(presentation.tabs.tabs.filter { $0.kind == .website }) { tab in
                if let browser = presentation.browsers[tab.id] {
                    VyronWorkspaceWebTab(browser: browser, tabID: tab.id)
                        .opacity(tab.id == selected.id ? 1 : 0)
                        .allowsHitTesting(tab.id == selected.id)
                        .disabled(tab.id != selected.id)
                        .accessibilityHidden(tab.id != selected.id)
                }
            }
            if selected.kind == .home {
                ScrollView {
                    VyronWorkspaceToolsView()
                        .frame(maxWidth: VyronWorkspaceToolsStyle.contentWidth)
                        .padding(VyronWorkspaceToolsStyle.sectionSpacing)
                        .frame(maxWidth: .infinity)
                }
            }
            if let session = presentation.pageSessions[selected.id] {
                VyronWorkspacePageTab(session: session, tabID: selected.id)
                    .id(selected.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            VyronBrowserText.closeUnsavedTitle,
            isPresented: Binding(
                get: { presentation.pendingCloseID != nil },
                set: { if !$0 { presentation.pendingCloseID = nil } }
            ),
            presenting: presentation.pendingCloseID
        ) { id in
            Button(VyronBrowserText.save) { presentation.savePendingClose(id) }
            Button(VyronBrowserText.discard, role: .destructive) { presentation.discardPendingClose(id) }
            Button(VyronBrowserText.cancel, role: .cancel) { presentation.pendingCloseID = nil }
        }
    }
}
