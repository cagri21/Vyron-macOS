import Foundation
import VyronModelDomain
import XCTest

final class VyronChatMessageRoleTests: XCTestCase {
    func testTypedRolesUseTheLegacyStringEncoding() throws {
        let user = ChatMessage(role: .user, content: "Inspect the project.", images: [])
        let assistant = ChatMessage(role: .assistant, content: "Ready.")

        XCTAssertNil(user.images)
        for (message, storedRole) in [(user, "user"), (assistant, "assistant")] {
            let data = try JSONEncoder().encode(message)
            let record = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(record["role"] as? String, storedRole)
            let restored = try JSONDecoder().decode(ChatMessage.self, from: data)
            XCTAssertEqual(restored, message)
        }
    }

    func testLegacyRolesDecodeWithoutLosingUnknownValues() throws {
        let legacy = """
        [
            {"id":"AF4E2C13-01BF-4B90-9A74-7E79AAC80F18","role":"user","content":"Inspect the project."},
            {"id":"AF4E2C13-01BF-4B90-9A74-7E79AAC80F19","role":"assistant","content":"Ready."},
            {"id":"AF4E2C13-01BF-4B90-9A74-7E79AAC80F20","role":"tool","content":"Internal result"}
        ]
        """
        let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(legacy.utf8))
        XCTAssertEqual(messages.map(\.conversationRole), [.user, .assistant, nil])

        let data = try JSONEncoder().encode(messages)
        let restored = try JSONDecoder().decode([ChatMessage].self, from: data)
        XCTAssertEqual(restored.map(\.role), ["user", "assistant", "tool"])
    }
}
