import Foundation
import VyronDevelopment

struct VyronInspectorChangeReview {
    let conversationID: UUID
    let workspacePath: String
    let changes: [DevelopmentChange]
    var selectedPath: String?
}
