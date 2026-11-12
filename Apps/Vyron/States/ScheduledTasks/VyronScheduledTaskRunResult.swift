import Foundation
import VyronCore

struct VyronScheduledTaskRunResult: Sendable {
    let state: VyronScheduledTaskRunState
    let conversationID: UUID?
    let detail: String?

    init(state: VyronScheduledTaskRunState, conversationID: UUID?, detail: String?) {
        self.state = state
        self.conversationID = conversationID
        self.detail = detail
    }
}
