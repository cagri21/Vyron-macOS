import Foundation
@testable import VyronCore

actor VyronLocalAuthTestTransport: VyronLocalAuthTransport {
    private var records: [UUID: VyronLocalAuthCredentialRecord] = [:]
    private var handler: (@Sendable (URLRequest, Int) async throws -> VyronLocalAuthHTTPResponse)?
    private var conflictHook: (@Sendable () async -> Void)?
    private var conflicts = 0
    private(set) var requests: [URLRequest] = []

    func configure(_ handler: @escaping @Sendable (URLRequest, Int) async throws -> VyronLocalAuthHTTPResponse) {
        self.handler = handler
    }

    func conflict(count: Int, hook: (@Sendable () async -> Void)? = nil) {
        conflicts = count
        conflictHook = hook
    }

    func store(_ payload: String?, for id: UUID, revision: Int = 1) {
        records[id] = VyronLocalAuthCredentialRecord(revision: revision, encryptedPayload: payload)
    }

    func record(for id: UUID) -> VyronLocalAuthCredentialRecord {
        records[id] ?? VyronLocalAuthCredentialRecord(revision: 0, encryptedPayload: nil)
    }

    func data(for request: URLRequest) async throws -> VyronLocalAuthHTTPResponse {
        requests.append(request)
        if let handler { return try await handler(request, requests.count) }
        if request.url?.path == "/v1/session" {
            return try Self.response([
                "service": "vyron-local-auth", "schema_version": 1,
                "instance_id": "11111111-1111-4111-8111-111111111111",
                "has_encrypted_credentials": records.values.contains { $0.encryptedPayload != nil }
            ])
        }
        guard let name = request.url?.lastPathComponent, let id = UUID(uuidString: name) else {
            throw VyronLocalAuthError.invalidResponse
        }
        let current = record(for: id)
        if request.httpMethod == "GET" {
            return try Self.response([
                "revision": current.revision, "encrypted_payload": current.encryptedPayload as Any? ?? NSNull()
            ])
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        guard body?["expected_revision"] as? Int == current.revision else {
            return try Self.response(["error": "conflict"], status: 409)
        }
        if conflicts > 0 {
            conflicts -= 1
            records[id] = VyronLocalAuthCredentialRecord(
                revision: current.revision + 1, encryptedPayload: current.encryptedPayload
            )
            if let conflictHook { await conflictHook() }
            return try Self.response(["error": "conflict"], status: 409)
        }
        let payload = request.httpMethod == "DELETE" ? nil : body?["encrypted_payload"] as? String
        records[id] = VyronLocalAuthCredentialRecord(revision: current.revision + 1, encryptedPayload: payload)
        return try Self.response(["revision": current.revision + 1])
    }

    static func response(_ value: [String: Any], status: Int = 200) throws -> VyronLocalAuthHTTPResponse {
        VyronLocalAuthHTTPResponse(statusCode: status, data: try JSONSerialization.data(withJSONObject: value))
    }
}
