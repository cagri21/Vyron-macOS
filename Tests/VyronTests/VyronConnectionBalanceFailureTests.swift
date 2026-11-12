import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConnectionBalanceFailureTests: XCTestCase {
    func testLocalUnsupportedAndDashboardOnlyNeverRetrieveCredentialsOrCallRepository() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let local = ModelConnectionProfile(
            name: "Local", kind: .ollama, endpoint: "http://localhost:11434", selectedModel: "fixture-model"
        )
        let unsupported = test.profile("Custom server", endpoint: "https://example.test/v1")
        let dashboard = test.profile("OpenAI", endpoint: "https://api.openai.com/v1")
        let profiles = [local, unsupported, dashboard]
        test.model.configure(profiles: profiles, activeID: local.id)
        test.model.start()
        for profile in profiles {
            test.model.configure(profiles: profiles, activeID: profile.id)
            test.model.refresh(profile.id)
            test.model.responseCompleted(profile.id)
            test.model.credentialChanged(profile.id)
            XCTAssertNil(test.model.state(for: profile.id).snapshot)
            XCTAssertFalse(test.model.canRefresh(profile.id))
        }
        test.clock.advance(by: 600)
        try await test.settle()
        XCTAssertEqual(test.model.state(for: local.id).support, .local)
        XCTAssertEqual(test.model.state(for: unsupported.id).support, .unsupported)
        XCTAssertEqual(test.model.state(for: dashboard.id).support, .dashboardOnly)
        XCTAssertTrue(test.credentials.requests.isEmpty)
        let requests = await test.repository.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(test.clock.pendingSleepCount, 0)
    }

    func testMissingKeyShowsNoAmountStopsAutomaticAndCredentialChangeCanReturnRealZero() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.credentials.value = " \n "
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { test.model.state(for: profile.id).phase == .missingKey }
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        XCTAssertFalse(test.model.isStale(for: profile.id))
        test.clock.advance(by: 600)
        try await test.settle()
        let noRequests = await test.repository.requests
        XCTAssertTrue(noRequests.isEmpty)
        XCTAssertEqual(test.credentials.requests, [profile.id])
        XCTAssertEqual(test.clock.pendingSleepCount, 0)

        test.credentials.value = "fixture-balance-key"
        test.model.credentialChanged(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 1 }
        let snapshot = test.snapshot(amount: 0)
        await test.repository.complete(0, with: snapshot)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 0)
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.checkedAt, snapshot.checkedAt)
        XCTAssertEqual(test.credentials.requests, [profile.id, profile.id])
    }

    func testTransientErrorsKeepLastValueStaleAndUseBoundedExponentialBackoff() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        let saved = test.snapshot(amount: 14)
        await test.repository.complete(0, with: saved)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertFalse(test.model.isStale(for: profile.id))
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        let delays = [60, 120, 240, 300]
        for (index, delay) in delays.enumerated() {
            let requestIndex = index + 1
            await test.repository.fail(requestIndex, with: VyronConnectionBalanceError.connectionFailed)
            try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.connectionFailed) }
            try await test.settle()
            XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 14)
            XCTAssertEqual(test.model.state(for: profile.id).snapshot?.checkedAt, saved.checkedAt)
            XCTAssertTrue(test.model.isStale(for: profile.id))
            let next = test.clock.date.addingTimeInterval(TimeInterval(delay))
            try await test.waitUntil { test.clock.deadlines.contains(next) }
            test.clock.advance(by: TimeInterval(delay - 1))
            try await test.settle()
            let beforeRetry = await test.repository.requests
            XCTAssertEqual(beforeRetry.count, requestIndex + 1)
            test.clock.advance(by: 1)
            try await test.waitUntil { await test.repository.requests.count == requestIndex + 2 }
        }
        await test.repository.complete(5, with: test.snapshot(amount: 13))
        try await test.waitUntil {
            test.model.state(for: profile.id).phase == .ready
                && test.clock.deadlines.contains(test.clock.date.addingTimeInterval(60))
        }
        XCTAssertFalse(test.model.isStale(for: profile.id))
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 13)
    }

    func testAuthenticationFailureStopsAutomaticUntilManualRetryOrCredentialChange() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 5))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.fail(1, with: VyronConnectionBalanceError.authenticationFailed)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.authenticationFailed) }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 5)
        XCTAssertTrue(test.model.isStale(for: profile.id))
        for _ in 0..<5 {
            test.clock.advance(by: 60)
            test.model.responseCompleted(profile.id)
            try await test.settle()
        }
        let stopped = await test.repository.requests
        XCTAssertEqual(stopped.count, 2)
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        await test.repository.complete(2, with: test.snapshot(amount: 4))
        try await test.waitUntil {
            test.model.state(for: profile.id).phase == .ready
                && test.clock.deadlines.contains(test.clock.date.addingTimeInterval(60))
        }
        test.clock.advance(by: 60)
        try await test.waitUntil { await test.repository.requests.count == 4 }
        await test.repository.fail(3, with: VyronConnectionBalanceError.authenticationFailed)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.authenticationFailed) }
        test.model.credentialChanged(profile.id)
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        try await test.waitUntil { await test.repository.requests.count == 5 }
        await test.repository.complete(4, with: test.snapshot(amount: 3))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 3)
    }

    func testNoKeyLimitClearsPriorNumericValueAndKeepsNormalCadenceWithoutErrorBackoff() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile("OpenRouter", endpoint: "https://openrouter.ai/api/v1")
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 8, scope: .keyAllowance))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        for requestIndex in [1, 2] {
            await test.repository.fail(requestIndex, with: VyronConnectionBalanceError.noKeyLimit)
            try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.noKeyLimit) }
            try await test.settle()
            XCTAssertNil(test.model.state(for: profile.id).snapshot)
            let next = test.clock.date.addingTimeInterval(60)
            try await test.waitUntil { test.clock.deadlines.contains(next) }
            test.clock.advance(by: 59)
            try await test.settle()
            let before = await test.repository.requests
            XCTAssertEqual(before.count, requestIndex + 1)
            test.clock.advance(by: 1)
            try await test.waitUntil { await test.repository.requests.count == requestIndex + 2 }
        }
    }

    func testCredentialLookupFailureRetainsStaleValueWithoutHttpAndManualRetryCanRecover() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 12))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.credentials.fails = true
        test.model.refresh(profile.id)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .credentialUnavailable }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 12)
        XCTAssertTrue(test.model.isStale(for: profile.id))
        test.clock.advance(by: 600)
        test.model.responseCompleted(profile.id)
        try await test.settle()
        let failedLookup = await test.repository.requests
        XCTAssertEqual(failedLookup.count, 1)
        XCTAssertEqual(test.credentials.requests, [profile.id, profile.id])

        test.credentials.fails = false
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.complete(1, with: test.snapshot(amount: 11))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 11)
        XCTAssertFalse(test.model.isStale(for: profile.id))
    }

    func testProviderRetryAfterBeyondBackoffCapPreventsEarlyAutomaticRefresh() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        let retryAfter = test.clock.date.addingTimeInterval(600)
        await test.repository.fail(0, with: VyronConnectionBalanceRetryFailure(
            error: .rateLimited, retryAfter: retryAfter
        ))
        try await test.waitUntil {
            test.model.state(for: profile.id).phase == .failed(.rateLimited)
                && test.clock.deadlines.contains(retryAfter)
        }
        XCTAssertNil(test.model.state(for: profile.id).snapshot)
        test.clock.advance(by: 599)
        test.model.refresh(profile.id)
        try await test.settle()
        let beforeAllowed = await test.repository.requests
        XCTAssertEqual(beforeAllowed.count, 1)
        test.clock.advance(by: 1)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.complete(1, with: test.snapshot(amount: 9))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 9)
    }

    func testResponseBurstAndSwitchingAwayThenBackCannotBypassTransientBackoff() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        let retryAt = test.clock.date.addingTimeInterval(60)
        await test.repository.fail(0, with: VyronConnectionBalanceError.rateLimited)
        try await test.waitUntil {
            test.model.state(for: profile.id).phase == .failed(.rateLimited)
                && test.clock.deadlines.contains(retryAt)
        }
        for _ in 0..<5 { test.model.responseCompleted(profile.id) }
        try await test.settle()
        test.clock.advance(by: 5)
        try await test.settle()
        let afterCompletion = await test.repository.requests
        XCTAssertEqual(afterCompletion.count, 1)
        test.model.configure(profiles: [profile], activeID: nil)
        test.model.configure(profiles: [profile], activeID: profile.id)
        try await test.waitUntil { test.clock.deadlines.contains(retryAt) }
        try await test.settle()
        let afterSwitch = await test.repository.requests
        XCTAssertEqual(afterSwitch.count, 1)
        test.clock.advance(by: 54)
        try await test.settle()
        let beforeRetry = await test.repository.requests
        XCTAssertEqual(beforeRetry.count, 1)
        test.clock.advance(by: 1)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.complete(1, with: test.snapshot(amount: 7))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
    }
}
