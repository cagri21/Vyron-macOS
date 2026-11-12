import Foundation
import VyronLocalization
import VyronModelDomain

/// Contains connection descriptions and generation settings only. Credentials live in Keychain.
public struct ModelConnectionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL =
            fileURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VyronAI", isDirectory: true).appendingPathComponent("model-connections.json")
    }

    public func load() throws -> ModelConnectionState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ModelConnectionState() }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= VyronModelConnectionLimits.maximumStorageBytes else {
            throw ModelProviderError.invalidSettings(VyronModelDataText.connectionFileTooLarge)
        }
        return try JSONDecoder().decode(ModelConnectionState.self, from: Data(contentsOf: fileURL)).validated()
    }

    public func save(_ state: ModelConnectionState) throws {
        let validated = try state.validated()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(validated).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
