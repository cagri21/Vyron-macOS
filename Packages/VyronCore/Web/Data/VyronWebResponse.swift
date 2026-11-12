import Foundation

struct VyronWebResponse: Sendable {
    let url: URL
    let mediaType: String
    let body: Data
}
