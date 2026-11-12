import Foundation
import VyronCore
import WebKit

@MainActor
final class VyronWorkspaceBrowserReader: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let websiteScope: VyronWebsiteScope?
    private var activeID: UUID?
    private var navigation: WKNavigation?
    private let retiredNavigations = NSHashTable<WKNavigation>.weakObjects()
    private var approvedMainHost: String?
    private var approvedFrameHosts: Set<String> = []
    private var completion: CheckedContinuation<VyronWebPage, any Error>?
    private var loadTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(websiteScope: VyronWebsiteScope? = nil) {
        self.websiteScope = websiteScope
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: VyronWorkspaceBrowserReadPolicy.initialViewport, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func read(url: URL) async throws -> VyronWebPage {
        try Task.checkCancellation()
        guard allowsPage(url) else { throw VyronWebError.unsafeURL }
        let id = UUID()
        let page: VyronWebPage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                cancel()
                activeID = id
                completion = continuation
                start(url: url, id: id)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(id, with: .failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        return page
    }

    func cancel() {
        guard let activeID else { return }
        finish(activeID, with: .failure(CancellationError()))
    }

    private func allowsPage(_ url: URL) -> Bool {
        guard let websiteScope else { return true }
        return websiteScope.canonicalPageURL(url) != nil
    }

    private func start(url: URL, id: UUID) {
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: VyronWorkspaceBrowserReadPolicy.timeout)
                self?.finish(id, with: .failure(URLError(.timedOut)))
            } catch is CancellationError {
                return
            } catch {
                self?.finish(id, with: .failure(error))
            }
        }
        loadTask = Task { [weak self] in
            do {
                let validated = try await VyronWebURLPolicy.validatePublicHTTPS(url)
                guard let self, activeID == id else { return }
                approvedMainHost = VyronWorkspaceBrowserReadPolicy.httpsHost(for: validated)
                navigation = webView.load(URLRequest(url: url))
                if navigation == nil { finish(id, with: .failure(VyronWebError.unavailable)) }
            } catch {
                self?.finish(id, with: .failure(error))
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let id = activeID, let frame = navigationAction.targetFrame,
            let url = navigationAction.request.url, navigationAction.navigationType == .other,
            navigationAction.request.httpMethod == "GET" || navigationAction.request.httpMethod == nil
        else {
            decisionHandler(.cancel)
            return
        }
        guard !navigationAction.shouldPerformDownload else {
            decisionHandler(.cancel)
            if frame.isMainFrame {
                finish(id, with: .failure(VyronWorkspaceBrowserReadError(
                    message: VyronBrowserText.unsupportedDownload
                )))
            }
            return
        }
        let isMainFrame = frame.isMainFrame
        guard let host = VyronWorkspaceBrowserReadPolicy.httpsHost(for: url),
            !isMainFrame || allowsPage(url)
        else {
            decisionHandler(.cancel)
            if isMainFrame { finish(id, with: .failure(VyronWebError.unsafeURL)) }
            return
        }
        if isMainFrame ? host == approvedMainHost : approvedFrameHosts.contains(host) {
            decisionHandler(.allow)
            return
        }
        Task { [weak self] in
            do {
                try await VyronWebURLPolicy.validatePublicHTTPS(url)
                guard let self, activeID == id else {
                    decisionHandler(.cancel)
                    return
                }
                if isMainFrame {
                    approvedMainHost = host
                } else {
                    approvedFrameHosts.insert(host)
                }
                decisionHandler(.allow)
            } catch {
                decisionHandler(.cancel)
                if isMainFrame { self?.finish(id, with: .failure(error)) }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard let id = activeID else {
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationResponse.isForMainFrame
        guard let response = navigationResponse.response as? HTTPURLResponse, let url = response.url,
            let host = VyronWorkspaceBrowserReadPolicy.httpsHost(for: url), !isMainFrame || allowsPage(url),
            isMainFrame ? host == approvedMainHost : approvedFrameHosts.contains(host)
        else {
            decisionHandler(.cancel)
            if isMainFrame { finish(id, with: .failure(VyronWebError.unsafeURL)) }
            return
        }
        guard navigationResponse.canShowMIMEType
        else {
            decisionHandler(.cancel)
            if isMainFrame { finish(id, with: .failure(VyronWebError.unsupportedContent)) }
            return
        }
        guard isMainFrame else {
            decisionHandler(.allow)
            return
        }
        guard let mediaType = response.mimeType?.lowercased(),
            VyronWorkspaceBrowserReadPolicy.readableMediaTypes.contains(mediaType),
            response.value(forHTTPHeaderField: "Content-Disposition")?
                .trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment") != true
        else {
            decisionHandler(.cancel)
            finish(id, with: .failure(VyronWebError.unsupportedContent))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            decisionHandler(.cancel)
            let detail = HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            let message = response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
                ? VyronBrowserText.verificationRequired
                : VyronBrowserText.navigationFailed("\(response.statusCode) \(detail)")
            finish(id, with: .failure(VyronWorkspaceBrowserReadError(message: message)))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard activeID != nil, let navigation, !retiredNavigations.contains(navigation) else { return }
        if let previous = self.navigation, previous !== navigation { retiredNavigations.add(previous) }
        sampleTask?.cancel()
        self.navigation = navigation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let id = activeID, let navigation, navigation === self.navigation else { return }
        sampleTask?.cancel()
        sampleTask = Task { [weak self, weak navigation] in
            guard let self, let navigation else { return }
            do {
                let page = try await samplePage()
                guard !Task.isCancelled, navigation === self.navigation else { return }
                finish(id, with: .success(page))
            } catch {
                guard !Task.isCancelled, navigation === self.navigation else { return }
                finish(id, with: .failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(navigation, with: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(navigation, with: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let activeID else { return }
        finish(activeID, with: .failure(VyronWorkspaceBrowserReadError(message: VyronBrowserText.processTerminated)))
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            if let activeID { finish(activeID, with: .failure(URLError(.userAuthenticationRequired))) }
        }
    }

    private func samplePage() async throws -> VyronWebPage {
        var latest: VyronWebPage?
        var stableCount = 0
        for _ in 0..<VyronWorkspaceBrowserReadPolicy.sampleCount {
            try Task.checkCancellation()
            if let page = try await visiblePage() {
                let isStable = latest?.text == page.text && latest?.source == page.source && latest?.links == page.links
                stableCount = isStable ? stableCount + 1 : 1
                latest = page
                if stableCount >= VyronWorkspaceBrowserReadPolicy.stableSampleCount { return page }
            } else {
                latest = nil
                stableCount = 0
            }
            try await Task.sleep(for: VyronWorkspaceBrowserReadPolicy.sampleInterval)
        }
        guard let latest else { throw VyronWebError.unsupportedContent }
        return latest
    }

    private func visiblePage() async throws -> VyronWebPage? {
        let value = try await webView.callAsyncJavaScript(
            VyronWorkspaceBrowserReadPolicy.visibleContent,
            arguments: [
                "textLimit": VyronWorkspaceBrowserReadPolicy.textLimit,
                "titleLimit": VyronWorkspaceBrowserReadPolicy.titleLimit,
                "linkScanLimit": VyronWorkspaceBrowserReadPolicy.linkScanLimit,
                "linkLimit": VyronWebPageLinks.maximumCount,
                "linkURLLimit": VyronWebPageLinks.maximumURLBytes
            ],
            contentWorld: .defaultClient
        )
        guard let sample = value as? [String: Any], let documentURL = sample["url"] as? String,
            let documentTitle = sample["title"] as? String, let text = sample["text"] as? String,
            let state = sample["state"] as? String, let linkValues = sample["links"] as? [String]
        else {
            throw VyronWebError.unsupportedContent
        }
        if state == "signIn" { throw URLError(.userAuthenticationRequired) }
        if state == "challenge" {
            throw VyronWorkspaceBrowserReadError(message: VyronBrowserText.verificationRequired)
        }
        guard !text.isEmpty, let url = URL(string: documentURL), url == webView.url, allowsPage(url),
            VyronWorkspaceBrowserReadPolicy.httpsHost(for: url) == approvedMainHost
        else { return nil }
        let title = documentTitle.isEmpty ? url.host ?? url.absoluteString : documentTitle
        let source = VyronWebSource(
            title: title, url: url, excerpt: String(text.prefix(VyronWorkspaceBrowserReadPolicy.excerptLimit))
        )
        let candidates = linkValues.lazy.compactMap { URL(string: $0) }
        let links = try VyronWebPageLinks.sameSite(candidates, from: url)
        return VyronWebPage(source: source, text: text, links: links)
    }

    private func failed(_ navigation: WKNavigation?, with error: any Error) {
        guard let activeID, let navigation, navigation === self.navigation else { return }
        finish(activeID, with: .failure(error))
    }

    private func finish(_ id: UUID, with result: Result<VyronWebPage, any Error>) {
        guard activeID == id else { return }
        activeID = nil
        if let navigation { retiredNavigations.add(navigation) }
        navigation = nil
        approvedMainHost = nil
        approvedFrameHosts.removeAll()
        loadTask?.cancel()
        loadTask = nil
        sampleTask?.cancel()
        sampleTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if case .failure = result { webView.stopLoading() }
        let completion = self.completion
        self.completion = nil
        completion?.resume(with: result)
    }
}
