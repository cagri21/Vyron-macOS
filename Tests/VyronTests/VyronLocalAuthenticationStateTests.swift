import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronLocalAuthenticationStateTests: XCTestCase {
    func testEmptyProfilesCanSettleWithoutConfigurationOrRestoreActions() async {
        let test = VyronLocalAuthenticationTestHarness()
        XCTAssertEqual(test.model.status, .notConfigured)
        test.model.synchronize(connectionIDs: [], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let requests = await test.backup.synchronizations
        XCTAssertEqual(requests, [[]])
        let finished = await test.backup.finishSynchronization(0, result: .success(.init(status: .notConfigured)))
        XCTAssertTrue(finished)
        let settled = await test.waitForStatus(.notConfigured)
        XCTAssertTrue(settled)
        XCTAssertNil(test.model.failure)
        XCTAssertTrue(test.actions.attempts.isEmpty)
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        await test.cleanUp()
    }

    func testRejectedRestorationDoesNotRefreshProvider() async {
        let test = VyronLocalAuthenticationTestHarness()
        test.actions.acceptsRestoration = false
        let id = UUID()
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let finished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: id, key: "fixture-key")]
        )))
        XCTAssertTrue(finished)
        let settled = await test.waitForStatus(.connected)
        XCTAssertTrue(settled)
        XCTAssertEqual(test.actions.attempts.map(\.connectionID), [id])
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        await test.cleanUp()
    }

    func testRetryClearsSanitizedFailureAndReportsNewStatus() async {
        let test = VyronLocalAuthenticationTestHarness()
        let id = UUID()
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let firstStarted = await test.waitForSynchronizations(1)
        XCTAssertTrue(firstStarted)
        let firstFinished = await test.backup.finishSynchronization(
            0, result: .failure(VyronLocalAuthenticationUnexpectedTestError())
        )
        XCTAssertTrue(firstFinished)
        let failed = await test.waitForStatus(.unavailable)
        XCTAssertTrue(failed)
        XCTAssertEqual(test.model.failure, .unavailable)
        XCTAssertFalse(test.model.failure?.localizedDescription.contains("fixture-private-key") == true)

        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        XCTAssertEqual(test.model.status, .connecting)
        XCTAssertNil(test.model.failure)
        let secondStarted = await test.waitForSynchronizations(2)
        XCTAssertTrue(secondStarted)
        let secondFinished = await test.backup.finishSynchronization(1, result: .success(.init(status: .connected)))
        XCTAssertTrue(secondFinished)
        let recovered = await test.waitForStatus(.connected)
        XCTAssertTrue(recovered)
        XCTAssertNil(test.model.failure)
        await test.cleanUp()
    }

    func testTypedIntegrityFailureRemainsVisibleWithoutRawErrorDetails() async {
        let test = VyronLocalAuthenticationTestHarness()
        test.model.synchronize(connectionIDs: [UUID()], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let finished = await test.backup.finishSynchronization(0, result: .failure(VyronLocalAuthError.integrityFailed))
        XCTAssertTrue(finished)
        let failed = await test.waitForStatus(.unavailable)
        XCTAssertTrue(failed)
        XCTAssertEqual(test.model.failure, .integrityFailed)
        await test.cleanUp()
    }

    func testRestorationWriteFailureDoesNotRefreshProviderOrClaimSuccess() async {
        let test = VyronLocalAuthenticationTestHarness()
        test.actions.restorationFailure = .credentialsUnavailable
        let id = UUID()
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let finished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: id, key: "fixture-key")]
        )))
        XCTAssertTrue(finished)
        let failed = await test.waitForStatus(.unavailable)
        XCTAssertTrue(failed)
        XCTAssertEqual(test.model.failure, .credentialsUnavailable)
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        await test.cleanUp()
    }

    func testRemovalFailureCanRetryWithoutClaimingConfiguredService() async {
        let test = VyronLocalAuthenticationTestHarness()
        let id = UUID()
        let first = Task { await test.model.remove(connectionID: id) }
        let firstStarted = await test.waitForRemovals(1)
        XCTAssertTrue(firstStarted)
        let firstFinished = await test.backup.finishRemoval(0, result: .failure(VyronLocalAuthError.unavailable))
        XCTAssertTrue(firstFinished)
        await first.value
        XCTAssertEqual(test.model.status, .unavailable)
        XCTAssertEqual(test.model.failure, .unavailable)

        let retry = Task { await test.model.remove(connectionID: id) }
        let retryStarted = await test.waitForRemovals(2)
        XCTAssertTrue(retryStarted)
        XCTAssertNil(test.model.failure)
        let retryFinished = await test.backup.finishRemoval(1, result: .success(.notConfigured))
        XCTAssertTrue(retryFinished)
        await retry.value
        XCTAssertEqual(test.model.status, .notConfigured)
        XCTAssertNil(test.model.failure)
        await test.cleanUp()
    }
}
