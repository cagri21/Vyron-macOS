import XCTest
import VyronCore
@testable import Vyron

final class VyronConversationRequestContextTests: XCTestCase {
    func testDevelopmentContextFiltersToolProtocolAndKeepsQuotedExamples() {
        let quoted = "Example: `<tool_call><function=read_file>file.txt</function></tool_call>`"
        let fenced = "<tool_call><function=write_file>file.txt</function></tool_call>"
        let assistant = ChatMessage(role: "assistant", content: [
            "A visible answer.",
            "<tool_call><function=read_file>",
            "hidden protocol payload",
            "</function></tool_call>",
            quoted,
            "~~~text",
            fenced,
            "~~~"
        ].joined(separator: "\n"))
        let user = ChatMessage(role: "user", content: "Review the examples.")
        let ignored = ChatMessage(role: "tool", content: "ignored tool result")

        let context = VyronConversationRequestContext.developmentConversationContext([assistant, ignored, user])

        let expected = "assistant: A visible answer.\n\(quoted)\n~~~text\n\(fenced)\n~~~"
            + "\n\nuser: Review the examples."
        XCTAssertEqual(context, expected)
    }
}
