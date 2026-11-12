import Foundation

struct VyronDevelopmentTaskIdentity: Codable, Sendable, Equatable {
    let id: UUID
    let projectPath: String
    let originalGoal: String
    let startedAt: Date

    init(id: UUID = UUID(), projectPath: String, originalGoal: String, startedAt: Date = Date()) {
        self.id = id
        self.projectPath = projectPath
        self.originalGoal = originalGoal
        self.startedAt = startedAt
    }
}
