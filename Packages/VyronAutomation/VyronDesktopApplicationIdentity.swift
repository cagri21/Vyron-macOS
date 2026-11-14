import Foundation

struct VyronDesktopApplicationIdentity: Hashable, Sendable {
    let id: String
    let bundleIdentifier: String?
    let installationURL: URL?
}
