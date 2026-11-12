import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronOfficeReviewIntegrationTests: XCTestCase {
    func testDeclinedConversionShowsExactArgumentsAndNeverStartsEngineOrCreatesOutput() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let recorder = VyronOfficeReviewInvocationRecorder()
        let tools = try makeTools(directory: test.directory, project: test.project, recorder: recorder)
        let call = conversion()
        let input = test.project.appendingPathComponent("source.docx")
        let original = Data("Local Office source fixture".utf8)
        try original.write(to: input)
        let operation = Task { @MainActor in try await test.model.executeOfficeTool(call, tools: tools) }
        defer {
            operation.cancel()
            test.model.mcpConnections.respondToReview(false)
        }

        try await test.waitUntil { test.model.mcpConnections.pendingReview != nil }
        let review = try XCTUnwrap(test.model.mcpConnections.pendingReview)
        XCTAssertEqual(review.connectionName, VyronOfficeText.title)
        XCTAssertEqual(review.toolName, call.function.name)
        XCTAssertEqual(
            try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(review.arguments.utf8)),
            call.function.arguments
        )

        test.model.mcpConnections.respondToReview(false)
        let result = try await operation.value
        let count = await recorder.count

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, VyronOfficeText.actionDeclined)
        XCTAssertNil(test.model.mcpConnections.pendingReview)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: test.project.appendingPathComponent("result.pdf").path))
    }

    func testCancellationClearsOfficeReviewWithoutStartingEngineOrCreatingOutput() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let recorder = VyronOfficeReviewInvocationRecorder()
        let tools = try makeTools(directory: test.directory, project: test.project, recorder: recorder)
        try Data("Local Office source fixture".utf8).write(to: test.project.appendingPathComponent("source.docx"))
        let operation = Task { @MainActor in try await test.model.executeOfficeTool(conversion(), tools: tools) }
        defer {
            operation.cancel()
            test.model.mcpConnections.respondToReview(false)
        }
        try await test.waitUntil { test.model.mcpConnections.pendingReview != nil }

        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancelling native Office review must cancel the operation.")
        } catch is CancellationError {
            // Cancellation is distinct from a completed or declined Office operation.
        }
        let count = await recorder.count

        XCTAssertNil(test.model.mcpConnections.pendingReview)
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: test.project.appendingPathComponent("result.pdf").path))
    }

    private func conversion() -> DevelopmentToolCall {
        DevelopmentToolCall(name: "office_convert", arguments: [
            "input_path": .string("source.docx"), "output_path": .string("result.pdf")
        ])
    }

    private func makeTools(
        directory: URL,
        project: URL,
        recorder: VyronOfficeReviewInvocationRecorder
    ) throws -> VyronOfficeTools {
        let executable = directory.appendingPathComponent("python-review-fixture")
        try Data("#!/usr/bin/false\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let runtime = VyronOfficeRuntime(
            configuration: VyronOfficeConfiguration(pythonExecutable: executable.path),
            run: { _ in
                await recorder.record()
                throw CancellationError()
            }
        )
        return VyronOfficeTools(rootURL: project, runtime: runtime)
    }
}
