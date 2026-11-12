import SwiftUI

struct VyronWorkspaceWebNavigation: View {
    @ObservedObject var browser: VyronWorkspaceBrowserModel

    var body: some View {
        VyronWorkspaceAddressBar(
            navigation: VyronWorkspaceNavigationContext(
                address: browser.address, isLoading: browser.isLoading,
                canGoBack: browser.canGoBack, canGoForward: browser.canGoForward
            ),
            command: perform
        )
    }

    private func perform(_ command: VyronWorkspaceNavigationAction) {
        switch command {
        case .back: browser.goBack()
        case .forward: browser.goForward()
        case .reload: browser.reload()
        case .stop: browser.stop()
        }
    }
}
