import Foundation

public struct VyronLocalAuthConfiguration: Decodable, Sendable, Equatable {
    public let schemaVersion: Int
    public let endpoint: URL

    public init(endpoint: String = "http://127.0.0.1:8327", schemaVersion: Int = 1) throws {
        guard let url = URL(string: endpoint) else { throw VyronLocalAuthError.invalidConfiguration }
        self.schemaVersion = schemaVersion
        self.endpoint = url
        try validate()
    }

    func validate() throws {
        guard schemaVersion == VyronLocalAuthLimits.schemaVersion,
            endpoint.absoluteString == VyronLocalAuthLimits.endpoint else {
            throw VyronLocalAuthError.invalidConfiguration
        }
    }
}
