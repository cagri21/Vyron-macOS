import Foundation

final class VyronWebsiteSitemapParser: NSObject, XMLParserDelegate {
    private let scope: VyronWebsiteScope
    private let baseURL: URL
    private var depth = 0
    private var rootNamespace: String?
    private var isIndex = false
    private var isEntry = false
    private var locationText: String?
    private var locationBytes = 0
    private var locations: [URL] = []
    private var seen: Set<URL> = []

    private init(scope: VyronWebsiteScope, baseURL: URL) {
        self.scope = scope
        self.baseURL = baseURL
    }

    static func parse(_ data: Data, scope: VyronWebsiteScope, baseURL: URL) -> VyronWebsiteSitemapDocument? {
        guard data.count <= VyronWebLimits.responseBytes,
            let text = String(data: data, encoding: .utf8), !text.utf8.contains(0),
            text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil
        else { return nil }
        let parser = XMLParser(data: data)
        let delegate = VyronWebsiteSitemapParser(scope: scope, baseURL: baseURL)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), parser.parserError == nil else { return nil }
        return VyronWebsiteSitemapDocument(isIndex: delegate.isIndex, locations: delegate.locations)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        switch depth {
        case 1:
            guard elementName == "sitemapindex" || elementName == "urlset" else {
                parser.abortParsing()
                return
            }
            rootNamespace = namespaceURI
            isIndex = elementName == "sitemapindex"
        case 2:
            isEntry = namespaceURI == rootNamespace && elementName == (isIndex ? "sitemap" : "url")
        case 3:
            if isEntry, namespaceURI == rootNamespace, elementName == "loc",
                locations.count < VyronWebsiteSitemapLimits.pageCandidates {
                locationText = ""
                locationBytes = 0
            }
        default:
            locationText = nil
            if depth > VyronWebsiteSitemapLimits.maximumXMLDepth { parser.abortParsing() }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard depth == 3, locationText != nil else { return }
        locationBytes += string.utf8.count
        if locationBytes <= VyronWebsiteScope.maximumURLBytes {
            locationText?.append(string)
        } else {
            locationText = nil
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else {
            locationText = nil
            return
        }
        self.parser(parser, foundCharacters: text)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        defer { depth -= 1 }
        guard depth == 3, let locationText else { return }
        self.locationText = nil
        if let url = scope.canonicalPageURL(locationText, relativeTo: baseURL), seen.insert(url).inserted {
            locations.append(url)
        }
    }
}
