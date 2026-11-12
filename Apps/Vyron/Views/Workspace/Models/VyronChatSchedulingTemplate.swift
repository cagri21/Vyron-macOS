import Foundation
import VyronCore

struct VyronChatSchedulingTemplate: Identifiable {
    let conversationID: UUID
    let definition: VyronScheduledTaskDefinition

    var id: UUID { conversationID }
}
