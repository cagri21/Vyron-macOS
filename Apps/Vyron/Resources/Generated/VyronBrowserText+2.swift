// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronBrowserText {
    static var websiteAnalysisURLRequired: String {
        VyronResourceBundle.string("browserWebsiteAnalysisURLRequired", fallback: "Include the public HTTPS URL of the website to analyze.")
    }
    static var websiteDiscoveringPages: String {
        VyronResourceBundle.string("browserWebsiteDiscoveringPages", fallback: "Finding website pages")
    }
    static var websiteEvidenceLimit: String {
        VyronResourceBundle.string("browserWebsiteEvidenceLimit", fallback: "Some retrieved pages exceeded the space available for analysis in this reply.")
    }
    static var websiteNoReadablePages: String {
        VyronResourceBundle.string("browserWebsiteNoReadablePages", fallback: "No readable pages were available.")
    }
    static func websitePageLimit(_ p1: String) -> String {
        VyronResourceBundle.format(
            "browserWebsitePageLimit",
            fallback: "Vyron reached the %@-page limit. Additional discovered pages are still unread.",
            arguments: [p1]
        )
    }
    static var websitePagesAnalyzed: String {
        VyronResourceBundle.string("browserWebsitePagesAnalyzed", fallback: "Pages analyzed")
    }
    static var websitePagesUnreadable: String {
        VyronResourceBundle.string("browserWebsitePagesUnreadable", fallback: "Pages that could not be read")
    }
}
