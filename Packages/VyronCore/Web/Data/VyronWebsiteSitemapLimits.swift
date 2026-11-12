import Foundation

enum VyronWebsiteSitemapLimits {
    static let sitemapDocuments = 5
    static let pageCandidates = 200
    static let maximumXMLDepth = 64
    static let requestTimeout: TimeInterval = 4
    static let resourceTimeout: TimeInterval = 6
    static let metadataMediaTypes = [
        "text/plain", "application/xml", "text/xml", "application/gzip", "application/x-gzip", "application/octet-stream"
    ]
}
