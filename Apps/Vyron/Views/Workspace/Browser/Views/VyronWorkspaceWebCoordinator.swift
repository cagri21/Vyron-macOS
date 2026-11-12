import Foundation
import WebKit

@MainActor
final class VyronWorkspaceWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let browser: VyronWorkspaceBrowserModel
    var openedLink: (URL) -> Void
    private var appliedRequestID: UUID?
    private var activeID: UUID?
    private var navigation: WKNavigation?
    private var obsoleteNavigations = NSHashTable<WKNavigation>.weakObjects()
    private var observations: [NSKeyValueObservation] = []
    private weak var observedWebView: WKWebView?
    private var hasCommittedDocument = false
    private var isAttached = true

    init(browser: VyronWorkspaceBrowserModel, openedLink: @escaping (URL) -> Void) {
        self.browser = browser
        self.openedLink = openedLink
    }

    func observe(_ webView: WKWebView) {
        observedWebView = webView
        observations = [
            observation(webView, keyPath: \.url),
            observation(webView, keyPath: \.title),
            observation(webView, keyPath: \.canGoBack),
            observation(webView, keyPath: \.canGoForward)
        ]
    }

    func apply(_ request: VyronWorkspaceBrowserRequest, to webView: WKWebView) {
        guard isAttached, request.id != appliedRequestID else { return }
        retireNavigation()
        hasCommittedDocument = false
        appliedRequestID = request.id
        activeID = request.id
        webView.stopLoading()
        switch request.command {
        case .navigate(let location):
            navigation = webView.load(URLRequest(url: location.url))
        case .back:
            navigation = webView.goBack()
        case .forward:
            navigation = webView.goForward()
        case .reload:
            if let url = browser.url, webView.url != url {
                navigation = webView.load(URLRequest(url: url))
            } else {
                navigation = webView.reload()
            }
        case .stop:
            return
        }
        if navigation == nil { browser.cancelled(request.id) }
    }

    func detach() {
        isAttached = false
        observations.removeAll()
        observedWebView = nil
        activeID = nil
        navigation = nil
        obsoleteNavigations.removeAllObjects()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard isAttached, let navigation,
            !obsoleteNavigations.contains(navigation)
        else { return }
        if self.navigation !== navigation {
            retireNavigation()
            hasCommittedDocument = false
            activeID = browser.beginPageNavigation()
            self.navigation = navigation
        }
        if let activeID { browser.started(activeID) }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard owns(navigation), let activeID else { return }
        browser.updated(activeID, snapshot: snapshot(webView))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard owns(navigation), let activeID else { return }
        hasCommittedDocument = true
        browser.updated(activeID, snapshot: snapshot(webView))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard owns(navigation), let activeID else { return }
        hasCommittedDocument = true
        browser.finished(activeID, snapshot: snapshot(webView))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isAttached, let activeID else { return }
        browser.failed(activeID, message: VyronBrowserText.processTerminated)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        guard isAttached, let url = navigationAction.request.url,
            VyronWorkspaceBrowserPolicy.allowsNavigation(url, isMainFrame: isMainFrame)
        else {
            if isAttached, isMainFrame, let activeID {
                browser.failed(activeID, message: VyronBrowserText.invalidAddress)
            }
            decisionHandler(.cancel)
            return
        }
        guard !navigationAction.shouldPerformDownload else {
            if isMainFrame { failDownload() }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            openedLink(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard isAttached, let url = navigationResponse.response.url,
            VyronWorkspaceBrowserPolicy.allowsNavigation(url, isMainFrame: navigationResponse.isForMainFrame)
        else {
            if isAttached, navigationResponse.isForMainFrame, let activeID {
                browser.failed(activeID, message: VyronBrowserText.invalidAddress)
            }
            decisionHandler(.cancel)
            return
        }
        if !navigationResponse.canShowMIMEType {
            if navigationResponse.isForMainFrame { failDownload() }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard isAttached, navigationAction.targetFrame == nil,
            let url = navigationAction.request.url, VyronWorkspaceBrowserPolicy.allows(url)
        else { return nil }
        openedLink(url)
        return nil
    }

    private func owns(_ candidate: WKNavigation?) -> Bool {
        isAttached && candidate != nil && candidate === navigation
    }

    private func retireNavigation() {
        if let navigation { obsoleteNavigations.add(navigation) }
        navigation = nil
    }

    private func snapshot(_ webView: WKWebView) -> VyronWorkspaceBrowserSnapshot {
        VyronWorkspaceBrowserSnapshot(
            url: webView.url, title: webView.title,
            canGoBack: webView.canGoBack, canGoForward: webView.canGoForward
        )
    }

    private func observation<Value>(
        _ webView: WKWebView,
        keyPath: KeyPath<WKWebView, Value>
    ) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, self.isAttached,
                    self.observedWebView === webView, self.hasCommittedDocument,
                    let activeID = self.activeID, self.browser.generationID == activeID
                else { return }
                self.browser.updated(activeID, snapshot: self.snapshot(webView))
            }
        }
    }

    private func failed(_ navigation: WKNavigation?, error: Error) {
        guard owns(navigation), let activeID else { return }
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled {
            browser.cancelled(activeID)
        } else {
            browser.failed(activeID, message: VyronBrowserText.navigationFailed(error.localizedDescription))
        }
    }

    private func failDownload() {
        guard let activeID else { return }
        browser.failed(activeID, message: VyronBrowserText.unsupportedDownload)
    }
}
