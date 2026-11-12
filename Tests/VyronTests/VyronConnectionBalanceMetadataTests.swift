import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConnectionBalanceMetadataTests: XCTestCase {
    func testMetadataEditsPreservePendingRequestCachedBalanceAndProviderRetryDeadline() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        var profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        profile.name = "Renamed while loading"
        profile.selectedModel = "a-different-model"
        profile.settings.temperature = 0.2
        test.model.configure(profiles: [profile], activeID: profile.id)
        try await test.settle()
        let pendingRequests = await test.repository.requests
        let cancellations = await test.repository.cancelledRequests
        XCTAssertEqual(pendingRequests.count, 1)
        XCTAssertTrue(cancellations.isEmpty)
        await test.repository.complete(0, with: test.snapshot(amount: 12))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        let retryAt = test.clock.date.addingTimeInterval(600)
        await test.repository.fail(1, with: VyronConnectionBalanceRetryFailure(
            error: .rateLimited, retryAfter: retryAt
        ))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.rateLimited) }

        profile.name = "Another metadata edit"
        profile.selectedModel = "yet-another-model"
        profile.settings.maxOutputTokens = 1_024
        profile.endpoint = "https://api.deepseek.com"
        test.model.configure(profiles: [profile], activeID: profile.id)
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 12)
        XCTAssertEqual(test.model.state(for: profile.id).phase, .failed(.rateLimited))
        XCTAssertFalse(test.model.canRefresh(profile.id))
        test.model.responseCompleted(profile.id)
        try await test.settle()
        test.clock.advance(by: 599)
        test.model.refresh(profile.id)
        try await test.settle()
        let beforeDeadline = await test.repository.requests
        XCTAssertEqual(beforeDeadline.count, 2)
        XCTAssertEqual(test.credentials.requests.count, 2)
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 12)
        test.clock.advance(by: 1)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        await test.repository.complete(2, with: test.snapshot(amount: 11))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 11)
    }

    func testMetadataAndCanonicalPathChangesDoNotUnfreezeAuthenticationOrClearLastValue() async throws {
        let test = VyronBalanceTestHarness()
        addTeardownBlock { await test.cleanUp() }
        var profile = test.profile()
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.start()
        try await test.waitUntil { await test.repository.requests.count == 1 }
        await test.repository.complete(0, with: test.snapshot(amount: 5))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 2 }
        await test.repository.fail(1, with: VyronConnectionBalanceError.authenticationFailed)
        try await test.waitUntil { test.model.state(for: profile.id).phase == .failed(.authenticationFailed) }

        profile.name = "Renamed authentication failure"
        profile.selectedModel = "new-model-selection"
        profile.settings.contextTokens = 16_384
        profile.endpoint = "https://api.deepseek.com"
        test.model.configure(profiles: [profile], activeID: profile.id)
        test.model.responseCompleted(profile.id)
        test.clock.advance(by: 600)
        try await test.settle()
        let requests = await test.repository.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(test.credentials.requests.count, 2)
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 5)
        XCTAssertEqual(test.model.state(for: profile.id).phase, .failed(.authenticationFailed))
        XCTAssertTrue(test.model.isStale(for: profile.id))

        test.model.refresh(profile.id)
        try await test.waitUntil { await test.repository.requests.count == 3 }
        await test.repository.complete(2, with: test.snapshot(amount: 4))
        try await test.waitUntil { test.model.state(for: profile.id).phase == .ready }
        XCTAssertEqual(test.model.state(for: profile.id).snapshot?.amounts.first?.amount, 4)
    }
}
