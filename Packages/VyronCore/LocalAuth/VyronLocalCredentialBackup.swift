import Foundation

public actor VyronLocalCredentialBackup {
    private let configurationStore: any VyronLocalAuthConfigurationStoring
    private let credentials: any VyronLocalAuthCredentialStoring
    private let transport: any VyronLocalAuthTransport
    private var generation = UUID()

    public init(baseDirectory: URL? = nil) {
        configurationStore = VyronLocalAuthFileConfigurationStore(baseDirectory: baseDirectory)
        credentials = VyronLocalAuthKeychainCredentials()
        transport = VyronLocalAuthHTTPTransport()
    }

    public init(
        configurationStore: any VyronLocalAuthConfigurationStoring,
        credentials: any VyronLocalAuthCredentialStoring,
        transport: any VyronLocalAuthTransport
    ) {
        self.configurationStore = configurationStore
        self.credentials = credentials
        self.transport = transport
    }

    public func synchronize(connectionIDs: [UUID]) async throws -> VyronLocalCredentialBackupResult {
        generation = UUID()
        guard connectionIDs.count <= VyronLocalAuthLimits.maximumConnections else {
            throw VyronLocalAuthError.invalidConfiguration
        }
        guard let connection = try await connection() else {
            return VyronLocalCredentialBackupResult(status: .notConfigured)
        }
        var session = try await verifiedSession(connection)
        let pending = try configurationStore.pendingRemovals()
        for id in pending {
            try await removeRemote(id, connection: connection)
            try check(connection)
            try configurationStore.completeRemoval(id)
        }
        if !pending.isEmpty { session = try await verifiedSession(connection) }
        let ids = Set(connectionIDs).subtracting(pending).sorted { $0.uuidString < $1.uuidString }
        var records: [UUID: VyronLocalAuthCredentialRecord] = [:]
        var hasPrimaryKey = false
        for id in ids {
            records[id] = try await record(id, connection: connection)
            if !(try await credentials.modelKey(for: id)).isEmpty { hasPrimaryKey = true }
            try check(connection)
        }
        let hasCiphertext = session.hasEncryptedCredentials || records.values.contains { $0.encryptedPayload != nil }
        let encryptionKey = try await encryptionKey(
            connection: connection, hasCiphertext: hasCiphertext, requiresCreation: hasPrimaryKey
        )
        var restorations: [VyronLocalCredentialRestoration] = []
        if let encryptionKey {
            for id in ids {
                guard let initial = records[id] else { throw VyronLocalAuthError.invalidResponse }
                if let candidate = try await synchronizeRecord(
                    id, initial: initial, key: encryptionKey, connection: connection
                ) { restorations.append(candidate) }
            }
        }
        try check(connection)
        return VyronLocalCredentialBackupResult(status: .connected, restorations: restorations)
    }

    public func remove(connectionID: UUID) async throws -> VyronLocalAuthStatus {
        generation = UUID()
        guard try configurationStore.load() != nil else { return .notConfigured }
        // Persist intent before cancellation or network checks so an offline removal is retried after restart.
        try configurationStore.recordRemoval(connectionID)
        guard let connection = try await connection() else { return .notConfigured }
        _ = try await verifiedSession(connection)
        try await removeRemote(connectionID, connection: connection)
        try check(connection)
        try configurationStore.completeRemoval(connectionID)
        return .connected
    }

    private func connection() async throws -> VyronLocalAuthConnection? {
        try Task.checkCancellation()
        let revision = generation
        guard let configuration = try configurationStore.load() else { return nil }
        try configuration.validate()
        let saved = try await credentials.deviceSecret(for: .deviceToken)
        try check(revision)
        let bootstrap = try configurationStore.bootstrapToken()
        let token: Data
        if let saved {
            guard saved.count == VyronLocalAuthLimits.secretBytes, bootstrap == nil || bootstrap == saved else {
                throw VyronLocalAuthError.credentialsUnavailable
            }
            token = saved
        } else {
            guard let bootstrap else { throw VyronLocalAuthError.credentialsUnavailable }
            token = try await credentials.storeDeviceSecretIfMissing(bootstrap, for: .deviceToken)
            try check(revision)
            guard token == bootstrap, token.count == VyronLocalAuthLimits.secretBytes else {
                throw VyronLocalAuthError.credentialsUnavailable
            }
        }
        return VyronLocalAuthConnection(configuration: configuration, token: token, generation: revision)
    }

    private func encryptionKey(
        connection: VyronLocalAuthConnection,
        hasCiphertext: Bool,
        requiresCreation: Bool
    ) async throws -> Data? {
        guard hasCiphertext || requiresCreation else { return nil }
        let saved = try await credentials.deviceSecret(for: .encryptionKey)
        try check(connection)
        if let saved {
            guard saved.count == VyronLocalAuthLimits.secretBytes else { throw VyronLocalAuthError.credentialsUnavailable }
            return saved
        }
        guard !hasCiphertext else { throw VyronLocalAuthError.encryptionKeyMissing }
        let created = try await credentials.storeDeviceSecretIfMissing(VyronLocalAuthCipher.newKey(), for: .encryptionKey)
        try check(connection)
        guard created.count == VyronLocalAuthLimits.secretBytes else { throw VyronLocalAuthError.credentialsUnavailable }
        return created
    }

    private func synchronizeRecord(
        _ id: UUID,
        initial: VyronLocalAuthCredentialRecord,
        key: Data,
        connection: VyronLocalAuthConnection
    ) async throws -> VyronLocalCredentialRestoration? {
        var current = initial
        for attempt in 0..<VyronLocalAuthLimits.attempts {
            try check(connection)
            let primary = try await credentials.modelKey(for: id)
            try check(connection)
            let backup = try current.encryptedPayload.map { try VyronLocalAuthCipher.decrypt($0, connectionID: id, key: key) }
            if primary.isEmpty {
                guard let backup else { return nil }
                // Return only a candidate; the UI owner atomically rechecks profile/key ownership before restoring.
                return VyronLocalCredentialRestoration(connectionID: id, key: backup)
            }
            if primary == backup { return nil }
            let latest = try await credentials.modelKey(for: id)
            try check(connection)
            guard !latest.isEmpty else { return nil }
            let encrypted = try VyronLocalAuthCipher.encrypt(latest, connectionID: id, key: key)
            let response = try await mutation(
                id, record: .init(expectedRevision: current.revision, encryptedPayload: encrypted),
                method: "PUT", connection: connection
            )
            if response.statusCode == 409, attempt == 0 {
                current = try await record(id, connection: connection)
                continue
            }
            try validateMutation(response, previousRevision: current.revision)
            return nil
        }
        throw VyronLocalAuthError.conflict
    }

    private func removeRemote(_ id: UUID, connection: VyronLocalAuthConnection) async throws {
        for attempt in 0..<VyronLocalAuthLimits.attempts {
            let current = try await record(id, connection: connection)
            let response = try await mutation(
                id, record: .init(expectedRevision: current.revision), method: "DELETE", connection: connection
            )
            if response.statusCode == 409, attempt == 0 { continue }
            try validateMutation(response, previousRevision: current.revision)
            return
        }
        throw VyronLocalAuthError.conflict
    }

    private func verifiedSession(_ connection: VyronLocalAuthConnection) async throws -> VyronLocalAuthSession {
        let response = try await send(connection.request(path: "v1/session"), connection: connection)
        try requireSuccess(response)
        let session: VyronLocalAuthSession = try decode(response.data)
        try session.validate()
        return session
    }

    private func record(_ id: UUID, connection: VyronLocalAuthConnection) async throws -> VyronLocalAuthCredentialRecord {
        let response = try await send(connection.request(path: credentialPath(id)), connection: connection)
        try requireSuccess(response)
        let record: VyronLocalAuthCredentialRecord = try decode(response.data)
        try record.validate()
        return record
    }

    private func mutation(
        _ id: UUID,
        record: VyronLocalAuthCredentialMutation,
        method: String,
        connection: VyronLocalAuthConnection
    ) async throws -> VyronLocalAuthHTTPResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await send(
            connection.request(path: credentialPath(id), method: method, body: encoder.encode(record)),
            connection: connection
        )
    }

    private func send(_ request: URLRequest, connection: VyronLocalAuthConnection) async throws -> VyronLocalAuthHTTPResponse {
        try check(connection)
        let response: VyronLocalAuthHTTPResponse
        do { response = try await transport.data(for: request) }
        catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let known = error as? VyronLocalAuthError { throw known }
            throw VyronLocalAuthError.unavailable
        }
        try check(connection)
        guard response.data.count <= VyronLocalAuthLimits.responseBytes else { throw VyronLocalAuthError.invalidResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw VyronLocalAuthError.unauthorized }
        return response
    }

    private func requireSuccess(_ response: VyronLocalAuthHTTPResponse) throws {
        guard response.statusCode == 200 else {
            throw response.statusCode == 409 ? VyronLocalAuthError.conflict : VyronLocalAuthError.unavailable
        }
    }

    private func validateMutation(_ response: VyronLocalAuthHTTPResponse, previousRevision: Int) throws {
        try requireSuccess(response)
        let revision: VyronLocalAuthRevision = try decode(response.data)
        guard previousRevision < Int.max, revision.revision == previousRevision + 1 else {
            throw VyronLocalAuthError.invalidResponse
        }
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Value.self, from: data)
        } catch { throw VyronLocalAuthError.invalidResponse }
    }

    private func credentialPath(_ id: UUID) -> String { "v1/credentials/" + id.uuidString.lowercased() }

    private func check(_ connection: VyronLocalAuthConnection) throws { try check(connection.generation) }

    private func check(_ revision: UUID) throws {
        try Task.checkCancellation()
        guard revision == generation else { throw CancellationError() }
    }
}
