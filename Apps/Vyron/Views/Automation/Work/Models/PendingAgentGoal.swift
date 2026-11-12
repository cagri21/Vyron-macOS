import Foundation
import VyronCore

struct PendingAgentGoal: Identifiable {
    let id = UUID()
    let goal: String
    let effort: AgentEffort
    let conversationID: UUID
    let messageID: UUID
}
