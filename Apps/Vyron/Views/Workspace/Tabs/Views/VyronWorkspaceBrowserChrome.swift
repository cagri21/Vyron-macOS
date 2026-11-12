import SwiftUI

struct VyronWorkspaceBrowserChrome: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation

    var body: some View {
        Group {
            if let browser = presentation.selectedBrowser {
                VyronWorkspaceWebNavigation(browser: browser)
            } else {
                VyronWorkspaceAddressBar(navigation: VyronWorkspaceNavigationContext(), command: { _ in })
            }
        }
        .background(Palette.canvas)
    }
}
