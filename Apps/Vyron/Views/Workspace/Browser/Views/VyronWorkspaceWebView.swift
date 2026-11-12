import AppKit
import SwiftUI
import WebKit

/// Uses WebKit's browser session without injecting scripts or supplying model credentials.
struct VyronWorkspaceWebView: NSViewRepresentable {
    @ObservedObject var browser: VyronWorkspaceBrowserModel
    let openedLink: (URL) -> Void

    func makeCoordinator() -> VyronWorkspaceWebCoordinator {
        VyronWorkspaceWebCoordinator(browser: browser, openedLink: openedLink)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isEnabled = context.environment.isEnabled
        if !isEnabled, let responder = webView.window?.firstResponder as? NSView,
            responder === webView || responder.isDescendant(of: webView) {
            webView.window?.makeFirstResponder(nil)
        }
        webView.isHidden = !isEnabled
        context.coordinator.openedLink = openedLink
        if let request = browser.request { context.coordinator.apply(request, to: webView) }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: VyronWorkspaceWebCoordinator) {
        coordinator.detach()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
