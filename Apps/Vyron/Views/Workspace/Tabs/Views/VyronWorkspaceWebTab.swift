import SwiftUI

struct VyronWorkspaceWebTab: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @ObservedObject var browser: VyronWorkspaceBrowserModel
    let tabID: UUID

    var body: some View {
        VyronWorkspaceBrowserView(browser: browser, openedLink: { url in presentation.openWebsite(url) })
            .onChange(of: browser.address) { _, _ in syncLocation() }
            .onChange(of: browser.displayTitle) { _, _ in syncLocation() }
    }

    private func syncLocation() {
        guard let url = browser.url else { return }
        presentation.tabs.updateWebsiteLocation(VyronWorkspaceWebsiteUpdate(
            tabID: tabID, url: url, title: browser.displayTitle
        ))
    }
}
