@testable import VyronCore

struct VyronStagnationTestSummaryRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let systemPrompt: String?
}
