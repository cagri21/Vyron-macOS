import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentSummaryTests: XCTestCase {
    func testResponseWithoutChecksContainsOnlySanitizedAssistantText() {
        let summary = developmentVerifiedSummary(
            "    This setting shares API traffic with OpenAI.\n<tool_call>\n<|im_end|>\n",
            checks: []
        )

        XCTAssertEqual(summary, "    This setting shares API traffic with OpenAI.")
    }

    func testLatestSuccessfulCheckDoesNotAppendRoutineEvidence() {
        let checks = [
            DevelopmentVerification(command: "swift test", exitCode: 1, timedOut: false),
            DevelopmentVerification(command: "swift test", exitCode: 0, timedOut: false)
        ]

        let summary = developmentVerifiedSummary("Fixed the implementation.", checks: checks)

        XCTAssertEqual(summary, "Fixed the implementation.")
    }

    func testAssistantSuppliedVerificationDetailsRemainInTheResponse() {
        let answer = "Updated the parser. Verification: `swift test` passed (12 tests)."
        let checks = [DevelopmentVerification(command: "swift test", exitCode: 0, timedOut: false)]

        XCTAssertEqual(developmentVerifiedSummary(answer, checks: checks), answer)
    }

    func testLatestFailedCheckStillAppendsItsEvidence() {
        let checks = [
            DevelopmentVerification(command: "swift test", exitCode: 0, timedOut: false),
            DevelopmentVerification(command: "swift test", exitCode: 1, timedOut: false)
        ]

        let summary = developmentVerifiedSummary("The parser needs another repair.", checks: checks)

        XCTAssertEqual(
            summary,
            "The parser needs another repair.\n\nVerification: latest `swift test` failed (exit 1)."
        )
    }

    func testTimedOutCheckStillAppendsItsEvidenceEvenWithZeroExitCode() {
        let checks = [DevelopmentVerification(command: "swift build", exitCode: 0, timedOut: true)]

        let summary = developmentVerifiedSummary("The build could not finish.", checks: checks)

        XCTAssertEqual(
            summary,
            "The build could not finish.\n\nVerification: latest `swift build` timed out (exit 0)."
        )
    }

    func testSuccessClaimWithoutAnyCheckIsCorrected() {
        let summary = developmentVerifiedSummary("All tests passed.", checks: [])

        XCTAssertEqual(
            summary,
            "The changes are ready for review. A successful build or test has not been verified."
        )
    }

    func testEmptySanitizedResponseRetainsCompletionFallback() {
        XCTAssertEqual(developmentVerifiedSummary("\n<tool_call>\n<|im_end|>\n", checks: []), "Task finished.")
    }

    func testCorrectingAnUnsupportedClaimPreservesFindingsAndReviewedScope() {
        let finding = "Sources/Retry.swift:8 catches cancellation and retries forever."
        let scope = "Reviewed Sources/Retry.swift and Sources/History.swift; other files remain unread."
        let answer = finding + "\n\nAll tests passed.\n\n" + scope

        let summary = developmentVerifiedSummary(answer, checks: [])

        XCTAssertTrue(summary.contains(finding))
        XCTAssertTrue(summary.contains(scope))
        XCTAssertTrue(summary.contains("has not been verified"))
        XCTAssertFalse(summary.contains("All tests passed"))
    }

    func testReadOnlyAgentAnswerHasNoRoutineFooterOrChangeMetadata() async throws {
        let answer = "This setting shares API traffic with OpenAI."
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", content: answer)
        }

        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Explain the setting without changing files or running commands.",
            model: "fixture-coder",
            onEvent: { _ in },
            approveCommand: { _ in
                XCTFail("A read-only explanation must not request command execution.")
                return false
            }
        )

        XCTAssertEqual(result.finalMessage, answer)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.isComplete)
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronDevelopmentSummary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
