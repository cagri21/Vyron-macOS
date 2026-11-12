import Foundation

enum VyronWebLimits {
    static let queryBytes = 2_000
    static let responseBytes = 1_048_576
    static let pageCharacters = 20_000
    static let titleCharacters = 240
    static let excerptCharacters = 1_200
    static let searchResults = 10
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 30
    static let textMediaTypes = ["text/html", "application/xhtml+xml", "text/plain"]
    static let searchEndpoint = "https://html.duckduckgo.com/html/"
}
