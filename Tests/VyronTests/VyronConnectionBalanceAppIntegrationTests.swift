import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConnectionBalanceAppIntegrationTests: XCTestCase {
    func testMainCompletionRefreshesItsCapturedConnectionWithoutChangingTheNewSelection() async throws {
        let balance = VyronBalanceTestHarness()
        let test = VyronQueueTestHarness(balanceDependencies: balance.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await balance.cleanUp()
        }
        let first = balance.profile("First account")
        let second = balance.profile("Second account")
        test.model.modelSelection.connectionProfiles = [first, second]
        test.model.modelSelection.activeConnectionID = first.id
        XCTAssertEqual(test.model.connectionBalances.state(for: first.id).support, .deepSeek)
        XCTAssertTrue(balance.credentials.requests.isEmpty)
        let initial = await balance.repository.requests
        XCTAssertTrue(initial.isEmpty)
        test.model.connectionBalances.start()
        try await balance.waitUntil { await balance.repository.requests.count == 1 }
        await balance.repository.complete(0, with: balance.snapshot(amount: 10))
        try await balance.waitUntil { test.model.connectionBalances.state(for: first.id).phase == .ready }

        test.model.computerWork.automaticRequestRouting = false
        test.send("Explain this task.")
        try await balance.waitUntil { await test.provider.requests.count == 1 }
        test.model.modelSelection.activeConnectionID = second.id
        try await balance.waitUntil { await balance.repository.requests.count == 2 }
        await balance.repository.complete(1, with: balance.snapshot(amount: 20))
        try await balance.waitUntil { test.model.connectionBalances.state(for: second.id).phase == .ready }
        await test.provider.complete(0, answer: "The task explanation is complete.")
        try await balance.waitUntil { !test.model.foregroundRun.isGenerating }
        try await balance.settle()
        balance.clock.advance(by: 5)
        try await balance.waitUntil { await balance.repository.requests.count == 3 }
        let requests = await balance.repository.requests
        XCTAssertEqual(requests.last?.profile.id, first.id)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, second.id)
        XCTAssertEqual(test.model.connectionBalances.state(for: second.id).snapshot?.amounts.first?.amount, 20)
    }

    func testIndependentSideChatRefreshesItsOriginalConnectionAfterMainConnectionChanges() async throws {
        let balance = VyronBalanceTestHarness()
        let test = try VyronSideChatTestHarness(balanceDependencies: balance.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await balance.cleanUp()
        }
        let first = balance.profile("Side account")
        let second = balance.profile("New main account")
        test.model.modelSelection.connectionProfiles = [first, second]
        test.model.modelSelection.activeConnectionID = first.id
        test.model.connectionBalances.start()
        try await balance.waitUntil { await balance.repository.requests.count == 1 }
        await balance.repository.complete(0, with: balance.snapshot(amount: 11))
        try await balance.waitUntil { test.model.connectionBalances.state(for: first.id).phase == .ready }
        let sourceID = try XCTUnwrap(test.model.selectedConversationID)
        let sideID = try XCTUnwrap(test.model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(test.model.newSideChatSessions[sideID])
        XCTAssertEqual(session.configuration.connection.id, first.id)
        test.model.modelSelection.activeConnectionID = second.id
        try await balance.waitUntil { await balance.repository.requests.count == 2 }
        await balance.repository.complete(1, with: balance.snapshot(amount: 22))
        try await balance.waitUntil { test.model.connectionBalances.state(for: second.id).phase == .ready }
        session.draft = "Continue this independent question."
        session.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        await test.provider.complete(1, answer: "Independent answer.")
        try await test.waitUntil { !session.isGenerating }
        try await balance.settle()
        balance.clock.advance(by: 5)
        try await balance.waitUntil { await balance.repository.requests.count == 3 }
        let requests = await balance.repository.requests
        XCTAssertEqual(requests.last?.profile.id, first.id)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, second.id)
        XCTAssertEqual(session.configuration.connection.name, "Side account")
    }

    func testAppProfileRemovalInvalidatesPendingBalanceThroughItsObservedOwner() async throws {
        let balance = VyronBalanceTestHarness()
        let test = VyronQueueTestHarness(balanceDependencies: balance.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await balance.cleanUp()
        }
        let profile = balance.profile()
        test.model.modelSelection.connectionProfiles = [profile]
        test.model.modelSelection.activeConnectionID = profile.id
        test.model.connectionBalances.start()
        try await balance.waitUntil { await balance.repository.requests.count == 1 }
        test.model.modelSelection.connectionProfiles = []
        await balance.repository.complete(0, with: balance.snapshot(amount: 999))
        try await balance.settle()
        XCTAssertNil(test.model.connectionBalances.state(for: profile.id).snapshot)
        XCTAssertEqual(test.model.connectionBalances.state(for: profile.id).support, .unsupported)
        XCTAssertFalse(test.model.connectionBalances.canRefresh(profile.id))
        XCTAssertNil(test.model.connectionBalances.billingURL(for: profile.id))
    }
}
