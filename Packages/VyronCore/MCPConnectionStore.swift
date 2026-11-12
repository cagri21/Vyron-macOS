import Foundation
import Security
import LocalAuthentication

public struct MCPConnectionStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL? = nil) {
        self.fileURL =
            fileURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VyronAI", isDirectory: true).appendingPathComponent("mcp-connections.json")
    }

    public func load() throws -> [MCPConnectionProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        guard (size?.intValue ?? Int.max) <= 1_048_576 else {
            throw MCPError.configuration("The MCP connections file is too large.")
        }
        return try validated(JSONDecoder().decode([MCPConnectionProfile].self, from: Data(contentsOf: fileURL)))
    }

    public func save(_ profiles: [MCPConnectionProfile]) throws {
        let profiles = try validated(profiles)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validated(_ profiles: [MCPConnectionProfile]) throws -> [MCPConnectionProfile] {
        guard profiles.count <= 100, Set(profiles.map(\.id)).count == profiles.count else {
            throw MCPError.configuration("Saved MCP connections contain duplicate entries or too many servers.")
        }
        return try profiles.map { try $0.validated() }
    }
}

public struct MCPCredentialStore: Sendable {
    private let service: String
    public init(service: String = "com.vyron.mcp-connections") { self.service = service }

    public func load(for id: UUID) throws -> MCPConnectionSecrets {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return MCPConnectionSecrets() }
        guard status == errSecSuccess, let data = result as? Data else { throw credentialError }
        return try JSONDecoder().decode(MCPConnectionSecrets.self, from: data).validated()
    }

    public func save(_ secrets: MCPConnectionSecrets, for id: UUID) throws {
        let data = try JSONEncoder().encode(secrets.validated())
        guard data.count <= 262_144 else { throw MCPError.configuration("MCP credentials exceed the size limit.") }
        let query = baseQuery(id)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw credentialError }
        } else if update != errSecSuccess {
            throw credentialError
        }
    }

    public func remove(for id: UUID) throws {
        let result = SecItemDelete(baseQuery(id) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw credentialError }
    }

    private var credentialError: MCPError {
        .configuration(
            "MCP credentials could not be accessed in Keychain. Unlock your login keychain or enter the credentials again."
        )
    }
    private func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
