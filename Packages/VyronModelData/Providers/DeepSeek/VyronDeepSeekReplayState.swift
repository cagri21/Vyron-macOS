import Foundation
import VyronModelDomain

/// Binds private provider state to the exact semantic assistant exchange that produced it.
struct VyronDeepSeekReplayState: Codable {
    let content: String
    let calls: [DevelopmentToolCall]?
    let reasoning: String
}
