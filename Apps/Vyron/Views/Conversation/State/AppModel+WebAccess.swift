import Foundation
import VyronCore

extension AppModel {
    func webContext(for prompt: String, response: VyronResponseIdentity) async throws -> String {
        recordActivity(
            VyronControlText.searchingWeb,
            detail: String(prompt.prefix(300)),
            conversationID: response.conversationID,
            messageID: response.messageID
        )
        let query = prompt.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let requestedURLs = try Self.requestedWebURLs(in: prompt)
        let sources: [VyronWebSource]
        if requestedURLs.isEmpty {
            sources = try await webAccess.search(query: VyronConversationRequestContext.bytePrefix(query, limit: 500))
        } else {
            sources = requestedURLs.prefix(3).map {
                VyronWebSource(title: $0.host ?? $0.absoluteString, url: $0, excerpt: "User-supplied URL")
            }
        }
        try Task.checkCancellation()
        guard foregroundRun.owns(response) else { throw CancellationError() }
        let excerpts = sources.map { source in
            let excerpt = VyronConversationRequestContext.bytePrefix(source.excerpt, limit: 350)
            return "Title: \(source.title)\nURL: \(source.url.absoluteString)\nSearch excerpt: \(excerpt)"
        }.joined(separator: "\n\n")
        var evidence = VyronConversationRequestContext.bytePrefix(excerpts, limit: 5_000)
        for source in sources.prefix(3) {
            recordActivity(
                VyronControlText.readingWebPage,
                detail: source.url.absoluteString,
                conversationID: response.conversationID,
                messageID: response.messageID
            )
            do {
                let page = try await readWebEvidence(
                    at: source.url, allowsBrowser: !requestedURLs.isEmpty, response: response
                )
                try Task.checkCancellation()
                guard foregroundRun.owns(response) else { throw CancellationError() }
                evidence += "\n\nPage: \(page.source.url.absoluteString)\nRetrieved: \(page.retrievedAt.ISO8601Format())\n"
                    + VyronConversationRequestContext.bytePrefix(page.text, limit: 3_500)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !requestedURLs.isEmpty { throw error }
                evidence += "\n\nPage could not be read: \(source.url.absoluteString). Only its search excerpt is available."
            }
        }
        return """
        <web-evidence retrieved-at="\(Date().ISO8601Format())">
        \(VyronConversationRequestContext.bytePrefix(evidence, limit: 16_000))
        </web-evidence>
        """
    }

    static func requestedWebURLs(in prompt: String) throws -> [URL] {
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
            .compactMap(\.url).filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    func readWebEvidence(
        at url: URL,
        allowsBrowser: Bool,
        response: VyronResponseIdentity,
        websiteScope: VyronWebsiteScope? = nil
    ) async throws -> VyronWebPage {
        do {
            return try await webAccess.read(url: url)
        } catch VyronWebError.unsupportedContent where allowsBrowser && !isRunningScheduledTask {
            try Task.checkCancellation()
            guard foregroundRun.owns(response) else { throw CancellationError() }
            guard url.scheme?.lowercased() == "https", let readRenderedWebPage else {
                throw VyronWebError.unsupportedContent
            }
            return try await readRenderedWebPage(url, response, websiteScope)
        }
    }
}
