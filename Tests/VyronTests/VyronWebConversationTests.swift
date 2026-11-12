import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWebConversationTests: XCTestCase {
    func testPharmacyRequestUsesWebInAgentModeWithAnOpenProject() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.model.loadWorkspace(test.base.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "list me pharmacies in istanbul. 10 only"
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.finishReply()

        let queries = await test.access.searchQueries
        let reads = await test.access.readURLs
        let requests = await test.provider.receivedMessages
        let development = await test.provider.developmentRequests
        XCTAssertEqual(queries, ["list me pharmacies in istanbul. 10 only"])
        XCTAssertEqual(reads.map(\.absoluteString), ["https://example.com/pharmacies"])
        XCTAssertEqual(development, 0)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains { $0.content.contains("WEB_EVIDENCE_MARKER") })
        XCTAssertTrue(requests[0].contains { $0.content.contains("https://example.com/pharmacies") })
        XCTAssertEqual(test.model.messages.last?.content, "Web answer 1 grounded in supplied evidence.")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertNil(test.model.errorMessage)
    }

    func testWebFailureFinishesWithFailedActivityBeforeAnyModelReply() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unavailable)
        test.model.composer.draft = "Find pharmacies in Istanbul"

        test.model.send()
        try await test.finishReply()

        let requests = await test.provider.receivedMessages
        let reads = await test.access.readURLs
        XCTAssertTrue(requests.isEmpty, "A failed lookup must not ask the model to invent current information.")
        XCTAssertTrue(reads.isEmpty)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertTrue(test.model.messages.last?.content.contains(VyronWebError.unavailable.localizedDescription) == true)
        XCTAssertFalse(test.model.messages.last?.content.contains("Web answer") == true)
    }

    func testRequestedURLIsReadDirectlyWithoutSendingASearchQuery() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Read https://example.com/pharmacy and summarize its opening hours"

        test.model.send()
        try await test.finishReply()

        let queries = await test.access.searchQueries
        let reads = await test.access.readURLs
        let requests = await test.provider.receivedMessages
        XCTAssertTrue(queries.isEmpty)
        XCTAssertEqual(reads.map(\.absoluteString), ["https://example.com/pharmacy"])
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains { $0.content.contains("WEB_EVIDENCE_MARKER") })
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testDirectURLReadFailureDoesNotSendTheModelAnEmptyEvidenceClaim() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unsupportedContent)
        test.model.composer.draft = "Read https://example.com/pharmacy"

        test.model.send()
        try await test.finishReply()

        let requests = await test.provider.receivedMessages
        let queries = await test.access.searchQueries
        let reads = await test.access.readURLs
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(queries.isEmpty)
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
    }

    func testRetryAfterWebFailureUsesFreshEvidenceAndCompletes() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unavailable)
        test.model.composer.draft = "Find pharmacies in Istanbul"
        test.model.send()
        try await test.finishReply()
        let firstResponseID = try XCTUnwrap(test.model.messages.last?.id)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)

        await test.access.fail(with: nil)
        test.model.composer.draft = "Find pharmacies in Istanbul"
        test.model.send()
        try await test.finishReply()

        let queries = await test.access.searchQueries
        let requests = await test.provider.receivedMessages
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(test.model.messages.first { $0.id == firstResponseID }?.activity?.state, .failed)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(test.model.messages.last?.content, "Web answer 1 grounded in supplied evidence.")
        XCTAssertNil(test.model.errorMessage)
    }

    func testStoppedNoncooperativeLookupCannotOverwriteAReplacementResponse() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.holdSearch(1)
        test.model.composer.draft = "Find pharmacies in Istanbul"
        test.model.send()
        try await test.base.waitUntil { await test.access.searchQueries.count == 1 }
        let stoppedResponseID = try XCTUnwrap(test.model.messages.last?.id)
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .working)

        test.model.stopGeneration()
        let stoppedActivity = test.model.messages.last?.activity
        XCTAssertEqual(stoppedActivity?.state, .stopped)
        test.model.composer.draft = "Find restaurants in Istanbul"
        test.model.send()
        try await test.finishReply()
        let latestResponse = try XCTUnwrap(test.model.messages.last)
        XCTAssertNotEqual(latestResponse.id, stoppedResponseID)

        try await test.access.releaseSearch(1)
        try await test.base.waitUntil { await test.access.releasedSearches == 1 }
        // Let the canceled model task resume after its deliberately noncooperative web dependency.
        for _ in 0..<20 { await Task.yield() }

        let requests = await test.provider.receivedMessages
        let reads = await test.access.readURLs
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(reads.count, 1, "The old search must stop before reading a page.")
        XCTAssertEqual(test.model.messages.first { $0.id == stoppedResponseID }?.activity, stoppedActivity)
        XCTAssertEqual(test.model.messages.last, latestResponse)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertNil(test.model.errorMessage)
    }
}
