import Foundation

public struct ModelConnectionState: Codable, Equatable, Sendable {
    public var profiles: [ModelConnectionProfile]
    public var activeConnectionID: UUID?
    public var builtinSettings: ModelSettings

    public init(
        profiles: [ModelConnectionProfile] = [],
        activeConnectionID: UUID? = nil,
        builtinSettings: ModelSettings = ModelSettings()
    ) {
        self.profiles = profiles
        self.activeConnectionID = activeConnectionID
        self.builtinSettings = builtinSettings
    }
}
