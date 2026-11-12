import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronLocalAuthConflictTests: XCTestCase {
    func testConflictRetriesOnceUsingLatestPrimaryKeyAndRevision() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        await credentials.setPrimary("first-offline-key", for: id)
        await transport.conflict(count: 1) { await credentials.setPrimary("latest-offline-key", for: id) }
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        _ = try await backup.synchronize(connectionIDs: [id])
        let record = await transport.record(for: id)
        let keyValue = try await credentials.deviceSecret(for: .encryptionKey)
        let key = try XCTUnwrap(keyValue)
        XCTAssertEqual(try VyronLocalAuthCipher.decrypt(try XCTUnwrap(record.encryptedPayload), connectionID: id, key: key), "latest-offline-key")
        let requests = await transport.requests
        let writes = try requests.filter { $0.httpMethod == "PUT" }.map {
            try JSONSerialization.jsonObject(with: $0.httpBody ?? Data()) as? [String: Any]
        }
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0]?["expected_revision"] as? Int, 0)
        XCTAssertEqual(writes[1]?["expected_revision"] as? Int, 1)
    }

    func testPersistentConflictIsBoundedToTwoWrites() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        await credentials.setPrimary("offline-key", for: id)
        await transport.conflict(count: 10)
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        do {
            _ = try await backup.synchronize(connectionIDs: [id])
            XCTFail("Conflicts must have a bounded retry policy.")
        } catch { XCTAssertEqual(error as? VyronLocalAuthError, .conflict) }
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 2)
    }

    func testOfflineRemovalIsDurableAndFlushesBeforeLaterBackup() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let offline = VyronLocalAuthTestTransport()
        await offline.configure { _, _ in throw VyronLocalAuthError.unavailable }
        let id = UUID()
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: offline)
        do { _ = try await backup.remove(connectionID: id) } catch {
            XCTAssertEqual(error as? VyronLocalAuthError, .unavailable)
        }
        XCTAssertEqual(try configuration.pendingRemovals(), [id])
        let online = VyronLocalAuthTestTransport()
        let encryption = VyronLocalAuthCipher.newKey()
        await credentials.setSecret(encryption, account: .encryptionKey)
        await online.store(try VyronLocalAuthCipher.encrypt("old-offline-key", connectionID: id, key: encryption), for: id)
        await credentials.setPrimary("stale-primary-snapshot", for: id)
        let restarted = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: online)
        _ = try await restarted.synchronize(connectionIDs: [id])
        XCTAssertTrue(try configuration.pendingRemovals().isEmpty)
        let record = await online.record(for: id)
        let requests = await online.requests
        XCTAssertNil(record.encryptedPayload)
        XCTAssertEqual(record.revision, 2)
        XCTAssertEqual(requests.filter { $0.httpMethod == "DELETE" }.count, 1)
        XCTAssertFalse(requests.contains { $0.httpMethod == "PUT" })
    }

    func testCancelledRemovalStillRecordsIntentBeforeAnyRequest() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        let backup = VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
        let pending = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await backup.remove(connectionID: id)
        }
        do { _ = try await pending.value; XCTFail("Cancellation should stop before HTTP.") }
        catch is CancellationError {} catch { XCTFail("Expected cancellation.") }
        XCTAssertEqual(try configuration.pendingRemovals(), [id])
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
