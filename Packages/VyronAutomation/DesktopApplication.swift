import Foundation

public struct DesktopApplication: Identifiable, Hashable, Sendable {
    private let identity: VyronDesktopApplicationIdentity

    public let name: String
    public let processIdentifier: Int32

    public var id: String { identity.id }
    public var bundleIdentifier: String? { identity.bundleIdentifier }
    public var installationURL: URL? { identity.installationURL }

    public init(id: String, name: String, bundleIdentifier: String?, processIdentifier: Int32) {
        identity = VyronDesktopApplicationIdentity(id: id, bundleIdentifier: bundleIdentifier, installationURL: nil)
        self.name = name
        self.processIdentifier = processIdentifier
    }

    init(installedAt url: URL, name: String, bundleIdentifier: String) {
        identity = VyronDesktopApplicationIdentity(
            id: bundleIdentifier, bundleIdentifier: bundleIdentifier, installationURL: url
        )
        self.name = name
        processIdentifier = 0
    }
}
