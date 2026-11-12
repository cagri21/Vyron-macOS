import Foundation

public struct VyronWebClient: VyronWebAccessing {
    private let transport: any VyronWebTransport

    public init() {
        transport = VyronWebURLSessionTransport()
    }

    init(transport: any VyronWebTransport) {
        self.transport = transport
    }

    public func search(query: String) async throws -> [VyronWebSource] {
        try Task.checkCancellation()
        let query = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty, query.utf8.count <= VyronWebLimits.queryBytes,
            !query.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw VyronWebError.invalidQuery }
        guard var components = URLComponents(string: VyronWebLimits.searchEndpoint) else {
            throw VyronWebError.unavailable
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw VyronWebError.invalidQuery }
        let response = try await transport.fetch(url)
        try Task.checkCancellation()
        let html = try documentText(response)
        guard response.mediaType != "text/plain" else { throw VyronWebError.unsupportedContent }
        let results = try VyronWebHTML.searchSources(in: html, baseURL: response.url)
        guard !results.isEmpty else { throw VyronWebError.noResults }
        return results
    }

    public func read(url: URL) async throws -> VyronWebPage {
        try Task.checkCancellation()
        let target = try VyronWebURLPolicy.validated(url)
        let response = try await transport.fetch(target)
        try Task.checkCancellation()
        let document = try documentText(response)
        let isHTML = response.mediaType != "text/plain"
        let text = isHTML ? try VyronWebHTML.text(document) : document
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VyronWebError.unsupportedContent
        }
        let title = isHTML ? try VyronWebHTML.pageTitle(in: document) : nil
        let links = isHTML ? try VyronWebHTML.pageLinks(in: document, from: target) : []
        let boundedText = String(text.prefix(VyronWebLimits.pageCharacters))
        return VyronWebPage(
            source: VyronWebSource(title: title ?? target.host ?? target.absoluteString,
                                   url: target, excerpt: String(boundedText.prefix(VyronWebLimits.excerptCharacters))),
            text: boundedText,
            links: links
        )
    }

    private func documentText(_ response: VyronWebResponse) throws -> String {
        guard response.body.count <= VyronWebLimits.responseBytes else { throw VyronWebError.responseTooLarge }
        guard ["text/html", "application/xhtml+xml", "text/plain"].contains(response.mediaType) else {
            throw VyronWebError.unsupportedContent
        }
        guard let value = String(data: response.body, encoding: .utf8)
            ?? String(data: response.body, encoding: .windowsCP1252)
        else { throw VyronWebError.unsupportedContent }
        return value
    }
}
