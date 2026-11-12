import Foundation
import VyronCore

actor VyronWebConversationAccess: VyronWebAccessing {
    private(set) var searchQueries: [String] = []
    private(set) var readURLs: [URL] = []
    private(set) var releasedSearches = 0
    private var failure: VyronWebError?
    private var heldRequests = Set<Int>()
    private var continuations: [Int: CheckedContinuation<[VyronWebSource], Error>] = [:]

    func fail(with error: VyronWebError?) { failure = error }
    func holdSearch(_ request: Int) { heldRequests.insert(request) }

    func releaseSearch(_ request: Int) throws {
        heldRequests.remove(request)
        if let continuation = continuations.removeValue(forKey: request) {
            continuation.resume(returning: try sources())
            releasedSearches += 1
        }
    }

    func search(query: String) async throws -> [VyronWebSource] {
        searchQueries.append(query)
        let request = searchQueries.count
        if heldRequests.contains(request) {
            // Deliberately ignore cancellation to test AppModel's request identity guard.
            return try await withCheckedThrowingContinuation { continuations[request] = $0 }
        }
        if let failure { throw failure }
        return try sources()
    }

    func read(url: URL) async throws -> VyronWebPage {
        readURLs.append(url)
        if let failure { throw failure }
        let source = VyronWebSource(title: "Verified pharmacy directory", url: url,
                                    excerpt: "A directory returned by the web fixture.")
        return VyronWebPage(source: source, text: "WEB_EVIDENCE_MARKER: İstanbul pharmacy, 123 Example Street.")
    }

    private func sources() throws -> [VyronWebSource] {
        guard let url = URL(string: "https://example.com/pharmacies") else { throw VyronWebError.unsafeURL }
        return [VyronWebSource(title: "Pharmacy directory", url: url, excerpt: "Istanbul pharmacy listings.")]
    }
}
