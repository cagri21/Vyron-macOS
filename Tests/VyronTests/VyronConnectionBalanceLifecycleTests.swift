import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConnectionBalanceLifecycleTests: XCTestCase {
    func testConstructionAndConfigurationDoNotReadKeysUntilStartAndInFlightRequestsDeduplicate() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let active = test.profile()
        let inactive = test.profile("Other account")
        test.model.configure(profiles: [active, inactive], activeID: active.id)
        test.model.refresh(active.id)
        test.model.responseCompleted(active.id)
        test.model.credentialChanged(active.id)
        try await test.settle()
        XCTAssertTrue(test.credentials.requests.isEmpty)
        let initial = await test.repository.requests
        XCTAssertTrue(initial.isEmpty)
        XCTAssertNil(test.model.state(for: active.id).snapshot)

        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        for _ in 0..<5 {
            test.model.start()
            test.model.refresh(active.id)
            test.model.responseCompleted(active.id)
        }
        try await test.settle()
        let requests = await test.repository.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.profile.id, active.id)
        XCTAssertTrue(requests.first?.usedFixtureCredential == true)
        XCTAssertEqual(test.credentials.requests, [active.id])
        XCTAssertNil(test.model.state(for: inactive.id).snapshot)
    }

    func testActiveRefreshCadenceIsSixtySecondsAfterSettlementAndInactiveManualRefreshRunsOnce() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let active = test.profile()
        let inactive = test.profile("Other account")
        test.model.configure(profiles: [active, inactive], activeID: active.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 12))
        try await test.waitUntil {
            test.model.state(for: active.id).phase == .ready && !test.clock.deadlines.isEmpty
        }
        XCTAssertEqual(test.clock.deadlines.first, test.clock.date.addingTimeInterval(60))
        test.clock.advance(by: 59)
        try await test.settle()
        let beforeCadence = await test.repository.requests
        XCTAssertEqual(beforeCadence.count, 1)
        test.clock.advance(by: 1)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.complete(1, with: test.snapshot(amount: 11))
        try await test.waitUntil { test.model.state(for: active.id).phase == .ready }

        test.model.refresh(inactive.id)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        await test.repository.complete(2, with: test.snapshot(amount: 8))
        try await test.waitUntil { test.model.state(for: inactive.id).phase == .ready }
        try await test.waitUntil { test.clock.deadlines.contains(test.clock.date.addingTimeInterval(60)) }
        test.clock.advance(by: 60)
        try await test.waitUntil { await test.repository.requests.count == 4 }
        let requests = await test.repository.requests
        XCTAssertEqual(requests.map { $0.profile.id }, [active.id, active.id, inactive.id, active.id])
        XCTAssertEqual(test.model.state(for: inactive.id).snapshot?.amounts.first?.amount, 8)
    }

    func testResponseCompletionsCoalesceAtFiveSecondsAndDoNotDuplicateAnInFlightRefresh() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot())
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        for _ in 0..<5 { test.model.responseCompleted(profile.id) }
        try await test.waitUntil { test.clock.deadlines.contains(test.clock.date.addingTimeInterval(5)) }
        test.clock.advance(by: 4)
        try await test.settle()
        let beforeDebounce = await test.repository.requests
        XCTAssertEqual(beforeDebounce.count, 1)
        test.model.responseCompleted(profile.id)
        test.clock.advance(by: 1)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        for _ in 0..<5 {
            test.model.refresh(profile.id)
            test.model.responseCompleted(profile.id)
        }
        try await test.waitUntil { test.clock.deadlines.contains(test.clock.date.addingTimeInterval(5)) }
        test.clock.advance(by: 5)
        try await test.settle()
        let duringFlight = await test.repository.requests
        XCTAssertEqual(duringFlight.count, 2)
        await test.repository.complete(1, with: test.snapshot(amount: 9))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 9)
    }

    func testSwitchAndProfileEditCancelCapturedRequestsAndIgnoreTheirLateBalances() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let first = test.profile()
        let second = test.profile("OpenRouter", endpoint: "https://openrouter.ai/api/v1")
        test.model.configure(profiles: [first, second], activeID: first.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        test.model.configure(profiles: [first, second], activeID: second.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        var edited = second
        edited.endpoint = "https://api.deepseek.com/v1"
        edited.name = "Edited account"
        test.model.configure(profiles: [first, edited], activeID: edited.id)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        try await test.waitUntil {
            let cancelled = await test.repository.cancelledRequests
            return cancelled.contains(0) && cancelled.contains(1)
        }
        await test.repository.complete(2, with: test.snapshot(amount: 7))
        try await test.waitUntil { test.model.state(for: edited.id).phase == .ready }
        await test.repository.complete(0, with: test.snapshot(amount: 111))
        await test.repository.complete(1, with: test.snapshot(amount: 222, scope: .keyAllowance))
        try await test.settle()
        XCTAssertNil(test.model.state(for: first.id).snapshot)
        XCTAssertEqual(test.model.state(for: first.id).phase, .idle)
        XCTAssertEqual(test.model.state(for: edited.id).snapshot?.amounts.first?.amount, 7)
        XCTAssertEqual(test.model.state(for: edited.id).snapshot?.scope, .account)
        let requests = await test.repository.requests
        XCTAssertEqual(requests[2].profile.endpoint, edited.endpoint)
    }

    func testCredentialRotationClearsOldValueAndRemovalCannotBeResurrectedByLateResult() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 10))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        test.model.credentialChanged(profile.id)
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        await test.repository.complete(2, with: test.snapshot(amount: 6))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        await test.repository.complete(1, with: test.snapshot(amount: 999))
        try await test.settle()
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 6)
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 4 }
        test.model.configure(profiles: [], activeID: nil)
        try await test.waitUntil { await test.repository.cancelledRequests.contains(3) }
        await test.repository.complete(3, with: test.snapshot(amount: 123))
        try await test.settle()
        XCTAssertEqual(test.model.state(for: profile.id).support, .unsupported)
        XCTAssertEqual(test.model.state(for: profile.id).phase, .idle)
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        XCTAssertFalse(test.model.canRefresh(profile.id))
    }

    func testShutdownCancelsRequestAndTimersAndLateSuccessCannotChangeState() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        test.model.responseCompleted(profile.id)
        test.model.shutdown()
        try await test.waitUntil { await test.repository.cancelledRequests.contains(0) }
        await test.repository.complete(0, with: test.snapshot(amount: 999))
        test.clock.advance(by: 600)
        test.model.refresh(profile.id)
        test.model.responseCompleted(profile.id)
        test.model.credentialChanged(profile.id)
        test.model.start()
        try await test.settle()
        let requests = await test.repository.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        XCTAssertNotEqual(test.model.state(for: profile.id).phase, .refreshing)
        XCTAssertFalse(test.model.canRefresh(profile.id))
        XCTAssertEqual(test.clock.pendingSleepCount, 0)
    }

    func testChangingInactiveProviderCancelsItsRequestWithoutStartingAnotherOrClearingActiveCache() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let active = test.profile()
        let inactive = test.profile("Inactive account")
        test.model.configure(profiles: [active, inactive], activeID: active.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 10))
        try await test.waitUntil { test.model.state(for: active.id).phase == .ready }
        test.model.refresh(inactive.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        var edited = inactive
        edited.name = "Edited inactive account"
        edited.endpoint = "https://openrouter.ai/api/v1"
        test.model.configure(profiles: [active, edited], activeID: active.id)
        try await test.waitUntil { await test.repository.cancelledRequests.contains(1) }
        await test.repository.complete(1, with: test.snapshot(amount: 777))
        try await test.settle()
        let requests = await test.repository.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(test.model.state(for: inactive.id).snapshot)
        XCTAssertEqual(test.model.state(for: inactive.id).phase, .idle)
        XCTAssertEqual(test.model.state(for: active.id).snapshot?.amounts.first?.amount, 10)
        XCTAssertEqual(test.model.state(for: active.id).phase, .ready)
    }
}
