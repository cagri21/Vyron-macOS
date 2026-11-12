import SwiftUI

struct VyronWorkspaceBrowserView: View {
    @ObservedObject var browser: VyronWorkspaceBrowserModel
    let openedLink: (URL) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if let reader = browser.renderedReader {
                VyronWorkspaceBrowserReaderView(reader: reader)
            } else {
                VyronWorkspaceWebView(browser: browser, openedLink: openedLink)
            }
            if browser.isLoading {
                ProgressView(VyronBrowserText.loading)
                    .controlSize(.small)
                    .padding(VyronWorkspaceBrowserStyle.spacing)
                    .background(Palette.surface, in: Capsule())
                    .padding(VyronWorkspaceBrowserStyle.padding)
                    .allowsHitTesting(false)
            }
            if let message = browser.errorMessage {
                VStack(spacing: VyronWorkspaceBrowserStyle.spacing) {
                    Text(message)
                        .font(VyronWorkspaceBrowserStyle.messageFont)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button(VyronBrowserText.retry) { browser.reload() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: VyronWorkspaceBrowserStyle.messageWidth)
                .padding(VyronWorkspaceBrowserStyle.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
            }
        }
        .foregroundStyle(Palette.text)
        .background(Palette.canvas)
    }
}
