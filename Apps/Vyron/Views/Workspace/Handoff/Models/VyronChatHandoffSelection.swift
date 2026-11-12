import Foundation

struct VyronChatHandoffSelection: Equatable, Sendable {
    var projectPath: String
    var workspacePath: String
    var conversationID: UUID?

    init(projectPath: String, workspacePath: String, conversationID: UUID? = nil) {
        self.projectPath = projectPath
        self.workspacePath = workspacePath
        self.conversationID = conversationID
    }
}
