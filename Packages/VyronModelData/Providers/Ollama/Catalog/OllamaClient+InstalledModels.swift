import Foundation
import VyronLocalization
import VyronModelDomain

extension OllamaClient {
    public func installedModelIdentity(named name: String) async throws -> VyronOllamaInstalledModelIdentity {
        guard let identity = try await installedModelIdentityIfPresent(named: name) else {
            throw LocalAIError.modelNotInstalled(name)
        }
        return identity
    }

    public func installedModelIdentityIfPresent(named name: String) async throws -> VyronOllamaInstalledModelIdentity? {
        try Task.checkCancellation()
        guard !configuredConnection else { throw LocalAIError.invalidEndpoint }
        try Self.validateModelName(name)
        let installed = try await catalog(path: "tags")
        return try identity(named: name, in: installed)
    }

    public func deleteInstalledModel(
        _ original: VyronOllamaInstalledModelIdentity,
        keeping replacement: VyronOllamaInstalledModelIdentity
    ) async throws {
        try Task.checkCancellation()
        guard !configuredConnection else { throw LocalAIError.invalidEndpoint }
        try Self.validateModelName(original.name)
        try Self.validateModelName(replacement.name)
        guard !Self.sameInstalledTag(original.name, replacement.name), original.digest != replacement.digest else {
            throw LocalAIError.invalidResponse(VyronModelDataText.ollamaSameInstalledIdentity)
        }

        // Ollama deletes by tag. Check both manifest digests just before sending the request.
        let installed = try await catalog(path: "tags")
        for expected in [original, replacement] {
            guard let actual = try identity(named: expected.name, in: installed) else {
                throw LocalAIError.modelNotInstalled(expected.name)
            }
            guard actual.name == expected.name, actual.digest == expected.digest else {
                throw LocalAIError.invalidResponse(VyronModelDataText.ollamaInstalledIdentityChanged(expected.name))
            }
        }

        let tag = original.name.contains(":") ? original.name : original.name + ":latest"
        var request = try makeRequest(path: "delete", body: VyronOllamaDeleteRequest(model: tag))
        request.httpMethod = VyronModelHTTP.delete
        try Task.checkCancellation()
        let (bytes, response) = try await stream(request)
        defer { bytes.task.cancel() }
        try await validate(response: response, bytes: bytes)
    }

    private func identity(
        named name: String,
        in installed: [VyronOllamaModelPayload]
    ) throws -> VyronOllamaInstalledModelIdentity? {
        let matches = installed.filter { Self.sameInstalledTag($0.name, name) }
        guard let entry = matches.first else { return nil }
        guard !entry.isRemote else { throw LocalAIError.cloudModelNotAllowed }
        try Self.validateModelName(entry.name)
        guard matches.count == 1, let digest = entry.digest, !digest.isEmpty else {
            throw LocalAIError.invalidResponse(VyronModelDataText.ollamaInstalledIdentityUnavailable(name))
        }
        return VyronOllamaInstalledModelIdentity(model: entry.localModel, digest: digest)
    }

    private static func sameInstalledTag(_ first: String, _ second: String) -> Bool {
        ModelCatalog.sameInstalledName(first.lowercased(), second.lowercased())
    }
}
