import Foundation
import VyronCore

struct VyronWebsiteAnalysis {
    let evidence: String?
    let report: String

    init(crawl: VyronWebsiteCrawl) {
        let opening = "<web-evidence site-wide=\"true\">\n"
        let closing = "</web-evidence>"
        var available = VyronWebsiteAnalysisLimits.evidenceBytes - opening.utf8.count - closing.utf8.count
        var selected: [VyronWebPage] = []
        for page in crawl.pages {
            let cost = Self.header(for: page).utf8.count + VyronWebsiteAnalysisLimits.minimumExcerptBytes + 2
            guard available >= cost else { continue }
            available -= cost
            selected.append(page)
        }

        if selected.isEmpty {
            evidence = nil
        } else {
            let excerptBytes = min(
                VyronWebsiteAnalysisLimits.maximumExcerptBytes,
                VyronWebsiteAnalysisLimits.minimumExcerptBytes + available / selected.count
            )
            let entries = selected.map { page in
                Self.header(for: page)
                    + VyronConversationRequestContext.bytePrefix(page.text, limit: excerptBytes) + "\n\n"
            }
            evidence = opening + entries.joined() + closing
        }

        var sections = [Self.section(
            VyronBrowserText.websitePagesAnalyzed,
            urls: selected.map(\.source.url),
            empty: VyronBrowserText.websiteNoReadablePages
        )]
        if !crawl.unreadableURLs.isEmpty {
            sections.append(Self.section(VyronBrowserText.websitePagesUnreadable, urls: crawl.unreadableURLs))
        }
        if crawl.reachedPageLimit {
            sections.append(VyronBrowserText.websitePageLimit(String(VyronWebsiteCrawler.maximumPages)))
        }
        if selected.count < crawl.pages.count {
            sections.append(VyronBrowserText.websiteEvidenceLimit)
        }
        report = sections.joined(separator: "\n\n")
    }

    private static func header(for page: VyronWebPage) -> String {
        let title = VyronConversationRequestContext.bytePrefix(
            page.source.title, limit: VyronWebsiteAnalysisLimits.maximumTitleBytes
        )
        let retrievedAt = page.retrievedAt.ISO8601Format()
        return "Page: \(page.source.url.absoluteString)\nTitle: \(title)\nRetrieved: \(retrievedAt)\n"
    }

    private static func section(_ title: String, urls: [URL], empty: String = "") -> String {
        let lines = urls.map { "- <\($0.absoluteString)>" }
        return "## \(title)\n\n" + (lines.isEmpty ? empty : lines.joined(separator: "\n"))
    }
}
