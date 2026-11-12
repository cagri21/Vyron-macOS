import Foundation

public enum VyronWebError: Error, LocalizedError, Sendable, Equatable {
    case invalidQuery
    case unsafeURL
    case unavailable
    case unsupportedContent
    case responseTooLarge
    case noResults

    public var errorDescription: String? {
        switch self {
        case .invalidQuery: "Enter a web search using at most 2,000 bytes."
        case .unsafeURL: "Web access requires a public HTTPS website without credentials or a custom port."
        case .unavailable: "The website could not be reached. Check your internet connection or try again later."
        case .unsupportedContent: "This website did not return readable web text."
        case .responseTooLarge: "The web response exceeded the reading limit."
        case .noResults: "The search service returned no readable results. Try a different search."
        }
    }
}
