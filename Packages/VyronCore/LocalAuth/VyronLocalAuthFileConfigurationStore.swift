import Foundation

public struct VyronLocalAuthFileConfigurationStore: VyronLocalAuthConfigurationStoring {
    public let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("VyronAI", isDirectory: true).appendingPathComponent("LocalAuth", isDirectory: true)
    }

    public func load() throws -> VyronLocalAuthConfiguration? {
        guard let data = try VyronLocalAuthSecureFiles.read(
            directory: baseDirectory, name: "config.json", maximumBytes: VyronLocalAuthLimits.configurationBytes
        ) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let configuration = try decoder.decode(VyronLocalAuthConfiguration.self, from: data)
            try configuration.validate()
            return configuration
        } catch { throw VyronLocalAuthError.invalidConfiguration }
    }

    public func bootstrapToken() throws -> Data? {
        guard let data = try VyronLocalAuthSecureFiles.read(
            directory: baseDirectory, name: "bootstrap.token", maximumBytes: VyronLocalAuthLimits.bootstrapBytes
        ) else { return nil }
        return try VyronLocalAuthToken.decode(data)
    }

    public func pendingRemovals() throws -> [UUID] {
        try VyronLocalAuthSecureFiles.pendingRemovals(directory: baseDirectory)
    }

    public func recordRemoval(_ connectionID: UUID) throws {
        try VyronLocalAuthSecureFiles.updateRemovals(directory: baseDirectory, connectionID: connectionID, adding: true)
    }

    public func completeRemoval(_ connectionID: UUID) throws {
        try VyronLocalAuthSecureFiles.updateRemovals(directory: baseDirectory, connectionID: connectionID, adding: false)
    }
}
