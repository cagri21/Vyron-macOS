import SwiftUI
import WebKit

/// Displays the official account page. It never receives a model API key or injects scripts into the page.
struct VyronBillingWebView: NSViewRepresentable {
    @ObservedObject var browser: VyronBillingBrowserModel

    func makeCoordinator() -> VyronBillingWebCoordinator {
        VyronBillingWebCoordinator(browser: browser)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let request = browser.request, request.id != context.coordinator.requestID else { return }
        context.coordinator.begin(request.id)
        webView.stopLoading()
        context.coordinator.track(webView.load(URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData)))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: VyronBillingWebCoordinator) {
        coordinator.detach()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
