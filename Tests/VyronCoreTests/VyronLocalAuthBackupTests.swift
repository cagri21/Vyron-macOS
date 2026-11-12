import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronLocalAuthBackupTests: XCTestCase {
    func testAbsentConfigurationDoesNotReadSecretsOrMakeRequests() async throws {
        let configuration = try VyronLocalAuthTestConfiguration(configured: false)
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let result = try await client(configuration, credentials, transport).synchronize(connectionIDs: [UUID()])
        XCTAssertEqual(result.status, .notConfigured)
        let secretReads = await credentials.secretReads
        let requests = await transport.requests
        XCTAssertEqual(secretReads, 0)
        XCTAssertTrue(requests.isEmpty)
    }

    func testRemovingWhenUnconfiguredDoesNotCreatePendingIntentOrReadSecrets() async throws {
        let configuration = try VyronLocalAuthTestConfiguration(configured: false)
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let status = try await client(configuration, credentials, transport).remove(connectionID: UUID())
        XCTAssertEqual(status, .notConfigured)
        XCTAssertTrue(try configuration.pendingRemovals().isEmpty)
        let reads = await credentials.secretReads
        let requests = await transport.requests
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(requests.isEmpty)
    }

    func testEncryptedBackupSkipsUnchangedValuesAndReturnsCandidateAfterRestartWithoutWritingPrimary() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        let value = "offline-test-provider-key"
        await credentials.setPrimary(value, for: id)
        let first = client(configuration, credentials, transport)
        let initialResult = try await first.synchronize(connectionIDs: [id])
        XCTAssertEqual(initialResult.status, .connected)
        let record = await transport.record(for: id)
        let savedKey = try await credentials.deviceSecret(for: .encryptionKey)
        let key = try XCTUnwrap(savedKey)
        XCTAssertEqual(record.revision, 1)
        XCTAssertEqual(try VyronLocalAuthCipher.decrypt(try XCTUnwrap(record.encryptedPayload), connectionID: id, key: key), value)
        _ = try await first.synchronize(connectionIDs: [id])
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 1)
        XCTAssertFalse(requests.contains { String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains(value) == true })
        await credentials.setPrimary("", for: id)
        let restarted = client(configuration, credentials, transport)
        let restored = try await restarted.synchronize(connectionIDs: [id])
        XCTAssertEqual(restored.restorations, [VyronLocalCredentialRestoration(connectionID: id, key: value)])
        let primary = try await credentials.modelKey(for: id)
        XCTAssertEqual(primary, "", "Only the presentation owner may finally restore a candidate.")
    }

    func testExistingDifferentPrimaryRemainsAuthoritativeOverOldBackup() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        let key = VyronLocalAuthCipher.newKey()
        await credentials.setSecret(key, account: .encryptionKey)
        await credentials.setPrimary("new-offline-key", for: id)
        await transport.store(try VyronLocalAuthCipher.encrypt("old-offline-key", connectionID: id, key: key), for: id)
        let result = try await client(configuration, credentials, transport).synchronize(connectionIDs: [id])
        XCTAssertTrue(result.restorations.isEmpty)
        let primary = try await credentials.modelKey(for: id)
        let latest = await transport.record(for: id)
        XCTAssertEqual(primary, "new-offline-key")
        XCTAssertEqual(try VyronLocalAuthCipher.decrypt(try XCTUnwrap(latest.encryptedPayload), connectionID: id, key: key), primary)
    }

    func testExistingCiphertextWithoutMasterKeyFailsEvenWhenNoProfilesRemain() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        let id = UUID()
        await transport.store(try VyronLocalAuthCipher.encrypt("offline-old-key", connectionID: id, key: VyronLocalAuthCipher.newKey()), for: id)
        do {
            _ = try await client(configuration, credentials, transport).synchronize(connectionIDs: [])
            XCTFail("An existing vault must never silently receive a fresh encryption key.")
        } catch { XCTAssertEqual(error as? VyronLocalAuthError, .encryptionKeyMissing) }
        let key = try await credentials.deviceSecret(for: .encryptionKey)
        let requests = await transport.requests
        XCTAssertNil(key)
        XCTAssertFalse(requests.contains { $0.httpMethod == "PUT" })
    }

    func testKeychainErrorsFailClosedWithoutCreatingSecretsOrUsingBootstrapAsFallback() async throws {
        let configuration = try VyronLocalAuthTestConfiguration()
        let credentials = VyronLocalAuthTestCredentials()
        let transport = VyronLocalAuthTestTransport()
        await credentials.fail(with: .credentialsUnavailable)
        do {
            _ = try await client(configuration, credentials, transport).synchronize(connectionIDs: [UUID()])
            XCTFail("A denied Keychain read must remain an error.")
        } catch { XCTAssertEqual(error as? VyronLocalAuthError, .credentialsUnavailable) }
        let writes = await credentials.secretWrites
        let requests = await transport.requests
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(requests.isEmpty)
    }

    private func client(
        _ configuration: VyronLocalAuthTestConfiguration,
        _ credentials: VyronLocalAuthTestCredentials,
        _ transport: VyronLocalAuthTestTransport
    ) -> VyronLocalCredentialBackup {
        VyronLocalCredentialBackup(configurationStore: configuration, credentials: credentials, transport: transport)
    }
}
