import Combine
import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronEstimatedBalanceAppIntegrationTests: XCTestCase {
    func testAppDirectoryStoresEstimateAndRestoresItWithoutReadingACredential() async throws {
        let fixture = VyronEstimatedBalanceTestHarness()
        let test = VyronQueueTestHarness(balanceDependencies: fixture.fixture.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await fixture.cleanUp()
        }
        let profile = fixture.profile
        test.model.modelSelection.connectionProfiles = [profile]
        try test.model.modelSelection.persist(test.model.modelSelection.connectionState)
        try test.model.connectionBalances.setEstimatedBalance(10, for: profile.id)
        let handler = try XCTUnwrap(test.model.connectionBalances.estimates.usageHandler(for: profile))
        await handler(fixture.event())
        let reopened = AppModel(
            historyDirectory: test.directory, balanceDependencies: fixture.fixture.model.dependencies
        )
        addTeardownBlock { await reopened.connectionBalances.shutdown() }
        XCTAssertEqual(reopened.connectionBalances.estimatedBalance(for: profile.id)?.remainingUSD,
            Decimal(string: "9.99338"))
        XCTAssertTrue(fixture.fixture.credentials.requests.isEmpty)
        let requests = await fixture.fixture.repository.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testObservedProfileRemovalDeletesPersistedEstimateAndChildChangesPublishToBadgeOwner() async throws {
        let fixture = VyronEstimatedBalanceTestHarness()
        let test = VyronQueueTestHarness(balanceDependencies: fixture.fixture.model.dependencies)
        addTeardownBlock {
            await test.model.connectionBalances.shutdown()
            await test.cleanUp()
            await fixture.cleanUp()
        }
        let profile = fixture.profile
        test.model.modelSelection.connectionProfiles = [profile]
        var updates = 0
        let subscription = test.model.connectionBalances.objectWillChange.sink { updates += 1 }
        try test.model.connectionBalances.setEstimatedBalance(10, for: profile.id)
        let previous = updates
        let handler = try XCTUnwrap(test.model.connectionBalances.estimates.usageHandler(for: profile))
        await handler(fixture.event())
        XCTAssertGreaterThan(updates, previous)
        test.model.modelSelection.connectionProfiles = []
        let store = VyronEstimatedBalanceStore(fileURL: test.directory.appendingPathComponent("estimated-balances.json"))
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertNil(test.model.connectionBalances.estimatedBalance(for: profile.id))
        subscription.cancel()
    }
}
