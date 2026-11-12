import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronLocalAuthenticationLifecycleTests: XCTestCase {
    func testNewSynchronizationIgnoresCancelledOlderRestoration() async {
        let test = VyronLocalAuthenticationTestHarness()
        let oldID = UUID()
        let currentID = UUID()
        test.model.synchronize(connectionIDs: [oldID], actions: test.actions.actions)
        let oldStarted = await test.waitForSynchronizations(1)
        XCTAssertTrue(oldStarted)
        test.model.synchronize(connectionIDs: [currentID], actions: test.actions.actions)
        let currentStarted = await test.waitForSynchronizations(2)
        XCTAssertTrue(currentStarted)

        let oldFinished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: oldID, key: "fixture-old-key")]
        )))
        XCTAssertTrue(oldFinished)
        let currentFinished = await test.backup.finishSynchronization(1, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: currentID, key: "fixture-current-key")]
        )))
        XCTAssertTrue(currentFinished)
        let settled = await test.waitForStatus(.connected)
        XCTAssertTrue(settled)
        XCTAssertEqual(test.actions.attempts.map(\.connectionID), [currentID])
        XCTAssertEqual(test.actions.refreshedConnections, [[currentID]])
        await test.cleanUp()
    }

    func testMutationInvalidatesPendingRestoreAndSnapshotToken() async {
        let test = VyronLocalAuthenticationTestHarness()
        let id = UUID()
        let snapshot = test.model.mutationSnapshot(connectionIDs: [id])
        XCTAssertTrue(test.model.matchesMutation(connectionID: id, token: snapshot[id]))
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        test.model.invalidate(connectionID: id)
        XCTAssertFalse(test.model.matchesMutation(connectionID: id, token: snapshot[id]))
        XCTAssertFalse(test.model.matchesMutation(connectionID: UUID(), token: nil))
        let next = test.model.mutationSnapshot(connectionIDs: [id])
        XCTAssertNotEqual(next[id], snapshot[id])

        let finished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: id, key: "fixture-deleted-key")]
        )))
        XCTAssertTrue(finished)
        await test.cleanUp()
        XCTAssertTrue(test.actions.attempts.isEmpty)
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        XCTAssertEqual(test.model.status, .notConfigured)
    }

    func testShutdownRejectsLateRestoreAndFutureSynchronization() async {
        let test = VyronLocalAuthenticationTestHarness()
        let id = UUID()
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let pending = test.model.shutdown()
        let finished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: id, key: "fixture-late-key")]
        )))
        XCTAssertTrue(finished)
        await pending?.value
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let requests = await test.backup.synchronizations
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(test.actions.attempts.isEmpty)
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        XCTAssertEqual(test.model.status, .notConfigured)
        await test.cleanUp()
    }

    func testRemovalCancelsOutstandingRestoreAndKeepsDisabledStatus() async {
        let test = VyronLocalAuthenticationTestHarness()
        let id = UUID()
        test.model.synchronize(connectionIDs: [id], actions: test.actions.actions)
        let started = await test.waitForSynchronizations(1)
        XCTAssertTrue(started)
        let removal = Task { await test.model.remove(connectionID: id) }
        let removalStarted = await test.waitForRemovals(1)
        XCTAssertTrue(removalStarted)
        let synchronizationFinished = await test.backup.finishSynchronization(0, result: .success(.init(
            status: .connected,
            restorations: [.init(connectionID: id, key: "fixture-deleted-key")]
        )))
        XCTAssertTrue(synchronizationFinished)
        let removalFinished = await test.backup.finishRemoval(0, result: .success(.notConfigured))
        XCTAssertTrue(removalFinished)
        await removal.value
        XCTAssertEqual(test.model.status, .notConfigured)
        XCTAssertNil(test.model.failure)
        XCTAssertTrue(test.actions.attempts.isEmpty)
        XCTAssertTrue(test.actions.refreshedConnections.isEmpty)
        await test.cleanUp()
    }

    func testShutdownDoesNotPublishLateRemovalSuccess() async {
        let test = VyronLocalAuthenticationTestHarness()
        let removal = Task { await test.model.remove(connectionID: UUID()) }
        let started = await test.waitForRemovals(1)
        XCTAssertTrue(started)
        let pending = test.model.shutdown()
        let finished = await test.backup.finishRemoval(0, result: .success(.connected))
        XCTAssertTrue(finished)
        await pending?.value
        await removal.value
        XCTAssertEqual(test.model.status, .notConfigured)
        await test.cleanUp()
    }
}
