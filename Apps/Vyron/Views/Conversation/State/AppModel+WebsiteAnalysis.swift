import Foundation
import VyronCore

extension AppModel {
    func websiteAnalysis(for prompt: String, response: VyronResponseIdentity) async throws -> VyronWebsiteAnalysis {
        guard let url = try Self.requestedWebURLs(in: prompt).first else {
            throw VyronWorkspaceBrowserReadError(message: VyronBrowserText.websiteAnalysisURLRequired)
        }
        let scope = try VyronWebsiteScope(seedURL: url)
        recordActivity(
            VyronBrowserText.websiteDiscoveringPages,
            detail: scope.rootURL.absoluteString,
            conversationID: response.conversationID,
            messageID: response.messageID
        )
        let sitemap: [URL]
        do {
            sitemap = try await webAccess.sitemapPages(in: scope)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Internal links still provide discovery when sitemap files are absent or unavailable.
            sitemap = []
        }
        try requireWebsiteResponse(response)

        let crawl = try await VyronWebsiteCrawler.crawl(in: scope, sitemap: sitemap) { [weak self] url in
            guard let self else { throw CancellationError() }
            return try await self.readWebsitePage(at: url, in: scope, response: response)
        }
        try requireWebsiteResponse(response)
        return VyronWebsiteAnalysis(crawl: crawl)
    }

    private func readWebsitePage(
        at url: URL,
        in scope: VyronWebsiteScope,
        response: VyronResponseIdentity
    ) async throws -> VyronWebPage {
        try requireWebsiteResponse(response)
        recordActivity(
            VyronControlText.readingWebPage,
            detail: url.absoluteString,
            conversationID: response.conversationID,
            messageID: response.messageID
        )
        let page = try await readWebEvidence(at: url, allowsBrowser: true, response: response, websiteScope: scope)
        try requireWebsiteResponse(response)
        return page
    }

    private func requireWebsiteResponse(_ response: VyronResponseIdentity) throws {
        try Task.checkCancellation()
        guard foregroundRun.owns(response) else { throw CancellationError() }
    }
}
