import Foundation

enum VyronWebHTML {
    static func searchSources(in html: String, baseURL: URL) throws -> [VyronWebSource] {
        let pattern = #"(?is)<a\b(?=[^>]*\bclass\s*=\s*["'][^"']*\bresult__a\b)[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        let anchors = try matches(pattern, in: html)
        let content = html as NSString
        var results: [VyronWebSource] = []
        var seen = Set<URL>()
        for (index, anchor) in anchors.enumerated() {
            let href = decoded(content.substring(with: anchor.range(at: 1)))
            guard let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                let target = searchTarget(resolved), seen.insert(target).inserted
            else { continue }
            let title = try text(content.substring(with: anchor.range(at: 2)))
            guard !title.isEmpty else { continue }
            let end = index + 1 < anchors.count ? anchors[index + 1].range.location : content.length
            let segment = content.substring(with: NSRange(location: NSMaxRange(anchor.range),
                                                         length: end - NSMaxRange(anchor.range)))
            let snippets = try matches(
                #"(?is)<(?:a|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*\bresult__snippet\b[^"']*["'][^>]*>(.*?)</(?:a|div|span)>"#,
                in: segment
            )
            let excerpt: String
            if let snippet = snippets.first {
                excerpt = try text((segment as NSString).substring(with: snippet.range(at: 1)))
            } else {
                excerpt = ""
            }
            results.append(VyronWebSource(
                title: String(title.prefix(VyronWebLimits.titleCharacters)),
                url: target,
                excerpt: String(excerpt.prefix(VyronWebLimits.excerptCharacters))
            ))
            if results.count == VyronWebLimits.searchResults { break }
        }
        return results
    }

    static func pageTitle(in html: String) throws -> String? {
        guard let result = try matches(#"(?is)<title\b[^>]*>(.*?)</title>"#, in: html).first else { return nil }
        let title = try text((html as NSString).substring(with: result.range(at: 1)))
        return title.isEmpty ? nil : String(title.prefix(VyronWebLimits.titleCharacters))
    }

    static func pageLinks(in html: String, from url: URL) throws -> [URL] {
        let markup = try replacing(
            #"(?is)<!--.*?(?:-->|$)|<(title|script|style|noscript|svg|template|textarea|iframe)(?=[\s>])[^>]*>.*?</\1\s*>"#,
            in: html, with: " "
        )
        let tags = try matches(#"(?is)<([a-z][a-z0-9:-]*)(?=[\s/>])((?:[^'"<>]|"[^"]*"|'[^']*')*)>"#, in: markup)
        let content = markup as NSString
        let attribute = try NSRegularExpression(
            pattern: #"(?:^|\s)([^\s=/"'<>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'<>`]+)))?"#,
            options: .caseInsensitive
        )
        let base = tags.lazy.filter { content.substring(with: $0.range(at: 1)).lowercased() == "base" }
            .compactMap { linkAttribute(in: content.substring(with: $0.range(at: 2)), matching: attribute) }
            .first.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL } ?? url
        let candidates = tags.lazy.compactMap { tag -> URL? in
            let name = content.substring(with: tag.range(at: 1)).lowercased()
            guard name == "a" || name == "area",
                let href = linkAttribute(
                    in: content.substring(with: tag.range(at: 2)), matching: attribute, skipsDownloads: true
                ),
                !href.isEmpty, href.utf8.count <= VyronWebPageLinks.maximumURLBytes
            else { return nil }
            return URL(string: href, relativeTo: base)?.absoluteURL
        }
        return try VyronWebPageLinks.sameSite(candidates, from: url)
    }

    static func text(_ html: String) throws -> String {
        var value = try replacing(#"(?is)<!--.*?-->|<(head|title|script|style|noscript|svg|template)(?=[\s>])[^>]*>.*?</\1\s*>"#,
                                  in: html, with: " ")
        value = try replacing(#"(?is)<[^>]+>"#, in: value, with: " ")
        value = decoded(value)
        return try replacing(#"\s+"#, in: value, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func linkAttribute(
        in attributes: String, matching expression: NSRegularExpression, skipsDownloads: Bool = false
    ) -> String? {
        let contents = attributes as NSString
        let range = NSRange(attributes.startIndex..., in: attributes)
        let values = expression.matches(in: attributes, range: range)
        guard !skipsDownloads || !values.contains(where: {
            contents.substring(with: $0.range(at: 1)).lowercased() == "download"
        }), let attribute = values.first(where: {
            contents.substring(with: $0.range(at: 1)).lowercased() == "href"
        })
        else { return nil }
        for index in 2...4 where attribute.range(at: index).location != NSNotFound {
            return decoded(contents.substring(with: attribute.range(at: index)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func searchTarget(_ url: URL) -> URL? {
        var target = url
        if let host = url.host?.lowercased(), host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com"),
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let destination = query.first(where: { $0.name == "uddg" })?.value,
            let unwrapped = URL(string: destination) {
            target = unwrapped
        }
        do { return try VyronWebURLPolicy.validated(target) }
        catch { return nil }
    }

    private static func matches(_ pattern: String, in value: String) throws -> [NSTextCheckingResult] {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) throws -> String {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value),
                                                   withTemplate: replacement)
    }

    private static func decoded(_ value: String) -> String {
        let entities: [String: String] = [
            "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ",
            "ndash": "–", "mdash": "—", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“"
        ]
        var result = ""
        var cursor = value.startIndex
        while cursor < value.endIndex {
            guard value[cursor] == "&", let end = value[cursor...].prefix(16).firstIndex(of: ";") else {
                result.append(value[cursor])
                cursor = value.index(after: cursor)
                continue
            }
            let code = String(value[value.index(after: cursor)..<end])
            if let replacement = entities[code] {
                result += replacement
            } else if code.hasPrefix("#"), let scalar = numericEntity(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += value[cursor...end]
            }
            cursor = value.index(after: end)
        }
        return result
    }

    private static func numericEntity(_ code: String) -> UnicodeScalar? {
        let hexadecimal = code.hasPrefix("#x") || code.hasPrefix("#X")
        guard let number = UInt32(code.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
            number >= 32, number != 127
        else { return nil }
        return UnicodeScalar(number)
    }
}
