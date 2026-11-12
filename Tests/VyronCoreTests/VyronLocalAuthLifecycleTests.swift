import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronLocalAuthLifecycleTests: XCTestCase {
    func testServiceMarkerAndAuthorizationFailuresNeverUseProviderBodiesAsDiagnostics() async throws {
        for status in [200, 401, 403, 302, 500] {
            let configuration = try VyronLocalAuthTestConfiguration()
            let credentials = VyronLocalAuthTestCredentials()
            let transport = VyronLocalAuthTestTransport()
            await transport.configure { _, _ in
                VyronLocalAuthHTTPResponse(statusCode: status, data: Data("PRIVATE_BODY_AND_CREDENTIAL".utf8))
            }
            let backup = VyronLocalCredentialBackup(
                configurationStore: configuration, credentials: credentials, transport: transport
            )
            do {
                _ = try await backup.synchronize(connectionIDs: [UUID()])
                XCTFail("An unverified or unsuccessful service must never become connected.")
            } catch {
                let expected: VyronLocalAuthError = status == 200 ? .invalidResponse
                    : ([401, 403].contains(status) ? .unauthorized : .unavailable)
                XCTAssertEqual(error as? VyronLocalAuthError, expected)
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE_BODY_AND_CREDENTIAL"))
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMissingEncryptedVaultMarkerFailsClosed() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        await transport.configure { _, _ in
            try VyronLocalAuthTestTransport.response([
                "service": "vyron-local-auth", "schema_version": 1,
                "instance_id": UUID().uuidString
            ])
        }
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        do { _ = try await backup.synchronize(connectionIDs: []); XCTFail("The vault marker is required.") }
        catch { XCTAssertEqual(error as? VyronLocalAuthError, .invalidResponse) }
    }

    func testAStaleUncooperativeResponseCannotUpdateOrReturnRestorations() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let gate = VyronLocalAuthTestGate()
        await transport.configure { _, number in
            if number == 1 { await gate.pause() }
            return try VyronLocalAuthTestTransport.response([
                "service": "vyron-local-auth", "schema_version": 1,
                "instance_id": UUID().uuidString, "has_encrypted_credentials": false
            ])
        }
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        let first = Task { try await backup.synchronize(connectionIDs: []) }
        await gate.waitForPause()
        let second = try await backup.synchronize(connectionIDs: [])
        XCTAssertEqual(second.status, .connected)
        await gate.resume()
        do { _ = try await first.value; XCTFail("A superseded operation cannot report success.") }
        catch is CancellationError {} catch { XCTFail("Supersession must retain cancellation semantics.") }
    }

    func testCancellationBeforeSynchronizationStopsBeforeKeychainOrHTTP() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await backup.synchronize(connectionIDs: [])
        }
        do { _ = try await task.value; XCTFail("Cancellation must remain distinct.") }
        catch is CancellationError {} catch { XCTFail("Expected cancellation.") }
        let reads = await credentials.secretReads
        let requests = await transport.requests
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(requests.isEmpty)
    }
}
