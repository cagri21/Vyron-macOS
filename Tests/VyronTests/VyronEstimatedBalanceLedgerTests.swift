import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronEstimatedBalanceLedgerTests: XCTestCase {
    func testReturnedTokenUsageDebitsExactDecimalAndDeduplicatesBothRequestAndResponse() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(10, for: id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        let event = test.event(observation: test.observation(responseID: "response-one"))
        await handler(event)
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "9.99338"))
        await handler(event)
        await handler(test.event(observation: test.observation(responseID: "response-one")))
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "9.99338"))
        XCTAssertFalse(try XCTUnwrap(test.balances.estimatedBalance(for: id)).hasUntrackedUsage)
    }

    func testConcurrentRequestsAndInactiveAccountAreEachDebitedToTheirCapturedConnection() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        var second = test.profile
        second.id = UUID()
        test.balances.configure(profiles: [test.profile, second], activeID: second.id)
        try test.balances.setEstimatedBalance(10, for: test.profile.id)
        try test.balances.setEstimatedBalance(20, for: second.id)
        let firstHandler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        let secondHandler = try XCTUnwrap(test.balances.estimates.usageHandler(for: second))
        let first = test.event()
        let another = test.event()
        let otherAccount = test.event(connectionID: second.id)
        async let one: Void = firstHandler(first)
        async let two: Void = firstHandler(another)
        async let three: Void = secondHandler(otherAccount)
        _ = await (one, two, three)
        XCTAssertEqual(test.balances.estimatedBalance(for: test.profile.id)?.remainingUSD, Decimal(string: "9.98676"))
        XCTAssertEqual(test.balances.estimatedBalance(for: second.id)?.remainingUSD, Decimal(string: "19.99338"))
    }

    func testMissingUsageOrUnknownPricingWarnsWithoutInventingFreeUsageAndResetClearsWarning() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(5, for: id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        await handler(test.event(observation: VyronOpenAIUsageObservation(
            responseID: nil, model: "gpt-6.1-sol", serviceTier: nil, result: .unavailable(.interrupted)
        )))
        await handler(test.event(observation: test.observation(model: "unpriced-custom-model")))
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, 5)
        XCTAssertTrue(try XCTUnwrap(test.balances.estimatedBalance(for: id)).hasUntrackedUsage)
        test.fixture.clock.advance(by: 10)
        try test.balances.setEstimatedBalance(12, for: id)
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, 12)
        XCTAssertFalse(try XCTUnwrap(test.balances.estimatedBalance(for: id)).hasUntrackedUsage)
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "11.99338"))
    }

    func testPreResetInflightResponseDoesNotDebitFreshBaselineButDisclosesUntrackedCost() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(10, for: id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        let inFlight = test.event()
        test.fixture.clock.advance(by: 10)
        try test.balances.setEstimatedBalance(25, for: id)
        await handler(inFlight)
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, 25)
        XCTAssertTrue(try XCTUnwrap(test.balances.estimatedBalance(for: id)).hasUntrackedUsage)
    }

    func testChangedCredentialInvalidatesSeedAndRejectsLateReceiptsFromPreviousAccount() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(10, for: id)
        let oldHandler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        test.balances.credentialChanged(id)
        XCTAssertNil(test.balances.estimatedBalance(for: id))
        try test.balances.setEstimatedBalance(20, for: id)
        await oldHandler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, 20)
        let newHandler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        await newHandler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "19.99338"))
    }

    func testMetadataKeepsEstimateButProviderChangeAndRemovalRejectLateResults() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(10, for: id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        var profile = test.profile
        profile.name = "Renamed"
        profile.selectedModel = "gpt-4.1"
        test.balances.configure(profiles: [profile], activeID: id)
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "9.99338"))
        profile.endpoint = "https://openrouter.ai/api/v1"
        test.balances.configure(profiles: [profile], activeID: id)
        XCTAssertNil(test.balances.estimatedBalance(for: id))
        test.balances.configure(profiles: [test.profile], activeID: id)
        try test.balances.setEstimatedBalance(30, for: id)
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, 30)
        let newHandler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        test.balances.configure(profiles: [], activeID: nil)
        await newHandler(test.event())
        XCTAssertNil(test.balances.estimatedBalance(for: id))
        XCTAssertFalse(test.balances.canSetEstimatedBalance(for: id))
    }

    func testShutdownRejectsLateUsageAndNegativeRemainingIsVisibleInsteadOfClamped() async throws {
        let test = VyronEstimatedBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let id = test.profile.id
        try test.balances.setEstimatedBalance(0, for: id)
        let handler = try XCTUnwrap(test.balances.estimates.usageHandler(for: test.profile))
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "-0.00662"))
        test.balances.shutdown()
        await handler(test.event())
        XCTAssertEqual(test.balances.estimatedBalance(for: id)?.remainingUSD, Decimal(string: "-0.00662"))
        XCTAssertFalse(test.balances.canSetEstimatedBalance(for: id))
    }
}
