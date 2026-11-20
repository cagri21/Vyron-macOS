import Foundation
import XCTest
import VyronDevelopment
import VyronModelDomain
@testable import VyronCore

@MainActor
final class VyronDevelopmentTaskPageResumeTests: XCTestCase {
    func testExplicitResumeRetainsAndPagesTheCompleteSavedGoal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronPagedResume-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let owner = UUID()
        let goal = "ORIGINAL_BEGIN\n" + String(repeating: "Respect the original constraint.\n", count: 800) + "ORIGINAL_END"
        var original = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: workspace.rootURL.path, originalGoal: goal
        ))
        original.finish(.failed)
        let store = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(owner.uuidString),
            projectPath: workspace.rootURL.path
        )
        try store.save(original)
        let provider = VyronSteeringTestProvider { round, messages in
            if round == 1 {
                return DevelopmentMessage(role: "assistant", toolCalls: [
                    DevelopmentToolCall(name: "resume_task", arguments: [:])
                ])
            }
            var start = 0
            var count = 1
            if let result = messages.last(where: { $0.role == "tool" && $0.toolName == "read_task" }) {
                let fields = try Self.object(result.content)
                if fields["next_page"] is NSNull {
                    return DevelopmentMessage(role: "assistant", content: "The complete saved task is available.")
                }
                start = try XCTUnwrap(fields["next_page"] as? Int)
                count = min(4, try XCTUnwrap(fields["total_pages"] as? Int) - start)
            }
            return DevelopmentMessage(role: "assistant", toolCalls: (start..<(start + count)).map { page in
                DevelopmentToolCall(name: "read_task", arguments: ["page": .number(Double(page))])
            })
        }
        let agent = DevelopmentAgent(client: provider, workspace: workspace)
        try await agent.configureSession(VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()))
        let request = "Use the earlier code review task."
        XCTAssertFalse(VyronDevelopmentContinuationContext.isContinuationRequest(request))
        let result = try await agent.run(
            goal: request, model: "fixture-coder", effort: .ultra, mode: .plan,
            onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertTrue(result.isComplete, result.finalMessage)
        let requests = await provider.recordedRequests()
        let messages: [DevelopmentMessage] = requests.flatMap { $0 }
        var pages = ""
        for message in messages where message.role == "tool" && message.toolName == "read_task" {
            let fields = try Self.object(message.content)
            pages += fields["output"] as? String ?? ""
        }
        XCTAssertTrue(pages.contains("ORIGINAL_BEGIN"))
        XCTAssertTrue(pages.contains("ORIGINAL_END"))
        XCTAssertEqual(try store.load(id: original.identity.id)?.identity.originalGoal, goal)
    }

    private nonisolated static func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
