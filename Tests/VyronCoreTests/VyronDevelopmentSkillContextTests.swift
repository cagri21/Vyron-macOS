import XCTest
@testable import VyronCore

final class VyronDevelopmentSkillContextTests: XCTestCase {
    func testSelectedSkillsRemainCompleteAlongsideBoundedConversation() throws {
        let skill = "Use all of these instructions.\n" + String(repeating: "skill guidance ", count: 600)
        let messages = developmentBaseMessages(
            system: "Existing permissions",
            goal: "/example Implement the feature",
            conversationContext: String(repeating: "older exchange ", count: 800),
            guidance: VyronDevelopmentSessionGuidance(skillContext: skill)
        )
        XCTAssertEqual(messages.first?.content, "Existing permissions")
        XCTAssertTrue(messages.last?.content.contains(skill) == true)
        XCTAssertTrue(messages.last?.content.contains("/example Implement the feature") == true)
        let compacted = try VyronDevelopmentExchangeCompactor.messages(base: messages, exchanges: [], forceCompact: true)
        XCTAssertTrue(compacted.last?.content.contains(skill) == true)
    }

    func testNoSelectedSkillPreservesExistingBaseMessage() {
        let messages = developmentBaseMessages(system: "Existing permissions", goal: "A normal task", conversationContext: nil)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.content, "A normal task")
    }
}
