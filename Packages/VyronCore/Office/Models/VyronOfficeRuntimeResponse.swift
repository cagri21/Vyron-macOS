import Foundation

/// The helper's JSON result is a transport representation, kept at the process boundary.
struct VyronOfficeRuntimeResponse: Decodable, Sendable {
    let ok: Bool
    let code: String
    let files: [String]?
    let warnings: [String]?
}
