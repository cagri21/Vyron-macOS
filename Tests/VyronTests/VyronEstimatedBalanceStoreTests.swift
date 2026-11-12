import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronEstimatedBalanceStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VyronEstimateTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testDecimalAmountsWarningsAndReceiptDeduplicationSurviveRelaunch() async throws {
        let store = VyronEstimatedBalanceStore(fileURL: try directory().appendingPathComponent("estimates.json"))
        let test = VyronEstimatedBalanceTestHarness(store: store)
        addTeardownBlock { await test.cleanUp() }
        try test.balances.setEstimatedBalance(try XCTUnwrap(Decimal(string: "12.12345678")), for: test.profile.id)
        let event = test.event(observation: test.observation(responseID: "persistent-response"))
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        await handler(event)
        let restored = VyronConnectionBalancesModel(dependencies: test.fixture.model.dependencies, estimateStore: store)
        addTeardownBlock { await restored.shutdown() }
        restored.configure(profiles: [test.profile], activeID: test.profile.id)
        XCTAssertEqual(restored.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "12.11683678"))
        let restoredHandler = try XCTUnwrap(restored.estimates.usageHandler(for: test.profile))
        await restoredHandler(event)
        await restoredHandler(test.event(observation: test.observation(responseID: "persistent-response")))
        XCTAssertEqual(restored.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "12.11683678"))
        let stored = try store.load()
        XCTAssertEqual(stored[test.profile.id]?.state, restored.estimatedBalance(for: test.profile.id))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptFileIsPreservedAndCannotBeOverwrittenByFreshSeed() async throws {
        let url = try directory().appendingPathComponent("estimates.json")
        let original = Data("not a valid ledger".utf8)
        try original.write(to: url)
        let test = VyronEstimatedBalanceTestHarness(store: VyronEstimatedBalanceStore(fileURL: url))
        addTeardownBlock { await test.cleanUp() }
        XCTAssertTrue(test.balances.estimateStorageError)
        XCTAssertFalse(test.balances.canSetEstimatedBalance(for: test.profile.id))
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(10, for: test.profile.id))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testFailedSaveKeepsPreviousSeedAndReportsUnsavedSubsequentUsage() async throws {
        let url = try directory().appendingPathComponent("estimates.json")
        let test = VyronEstimatedBalanceTestHarness(store: VyronEstimatedBalanceStore(fileURL: url))
        addTeardownBlock { await test.cleanUp() }
        try test.balances.setEstimatedBalance(7, for: test.profile.id)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(20, for: test.profile.id))
        XCTAssertEqual(test.balances.estimatedBalance(for: test.profile.id)?.remainingUSD, 7)
        XCTAssertTrue(test.balances.estimateStorageError)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        let event = test.event()
        await handler(event)
        await handler(event)
        XCTAssertEqual(test.balances.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "6.99338"))
        XCTAssertTrue(test.balances.estimateStorageError)
    }

    func testInvalidAmountsAndUnsupportedConnectionsNeverCreateAnEstimate() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(-1, for: id))
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(.nan, for: id))
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(1_000_000_001, for: id))
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(10, for: UUID()))
        XCTAssertNil(test.balances.estimatedBalance(for: id))
        var local = test.profile
        local.endpoint = "http://localhost:1234/v1"
        test.balances.configure(profiles: [local], activeID: id)
        XCTAssertNil(test.balances.estimates.usageHandler(for: local))
        XCTAssertThrowsError(try test.balances.setEstimatedBalance(10, for: id))
    }

    func testShutdownSettlementAcceptsFinalUsageAndUnsettledShutdownPersistsWarning() async throws {
        let store = VyronEstimatedBalanceStore(fileURL: try directory().appendingPathComponent("estimates.json"))
        let test = VyronEstimatedBalanceTestHarness(store: store)
        addTeardownBlock { await test.cleanUp() }
        try test.balances.setEstimatedBalance(10, for: test.profile.id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        test.balances.shutdown(waitForUsage: true)
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "9.99338"))
        test.balances.estimates.finishShutdown(hasUnsettledRequests: true)
        await handler(test.event())
        XCTAssertTrue(try XCTUnwrap(store.load()[test.profile.id]).state.hasUntrackedUsage)
        XCTAssertEqual(test.balances.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "9.99338"))
    }
}
