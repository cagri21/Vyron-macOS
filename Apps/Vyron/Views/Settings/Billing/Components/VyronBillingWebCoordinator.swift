import Foundation
import WebKit

@MainActor
final class VyronBillingWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let browser: VyronBillingBrowserModel
    private(set) var requestID: UUID?
    private var navigation: WKNavigation?

    init(browser: VyronBillingBrowserModel) { self.browser = browser }

    func begin(_ id: UUID) {
        requestID = id
        navigation = nil
    }

    func detach() {
        requestID = nil
        navigation = nil
    }

    func track(_ navigation: WKNavigation?) {
        guard let requestID else { return }
        guard let navigation else { browser.failed(requestID); return }
        self.navigation = navigation
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let requestID, self.navigation == nil || navigation === self.navigation else { return }
        self.navigation = navigation
        browser.loading(requestID)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let requestID, navigation === self.navigation else { return }
        browser.committed(requestID, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let requestID, navigation === self.navigation else { return }
        browser.finished(requestID)
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let requestID else { return }
        browser.failed(requestID)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        let result = VyronBillingNavigationPolicy.decision(for: navigationAction.request.url, isMainFrame: isMainFrame)
        switch result {
        case .allow:
            decisionHandler(.allow)
        case .browserRequired:
            if let requestID { browser.requiresBrowser(requestID) }
            decisionHandler(.cancel)
        case .block:
            if isMainFrame, let requestID { browser.failed(requestID) }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let requestID else { return nil }
        switch VyronBillingNavigationPolicy.decision(for: navigationAction.request.url, isMainFrame: true) {
        case .allow: track(webView.load(navigationAction.request))
        case .browserRequired: browser.requiresBrowser(requestID)
        case .block: browser.failed(requestID)
        }
        return nil
    }

    private func failed(_ navigation: WKNavigation?, error: Error) {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled {
            if navigation === self.navigation { self.navigation = nil }
            return
        }
        guard let requestID, navigation === self.navigation else { return }
        browser.failed(requestID)
    }
}
