import Foundation

struct VyronSkillLoadRequest: Equatable {
    let projectDirectory: URL?
    let refreshID: UUID
}
