import Foundation
import VyronDevelopment

public struct VyronDevelopmentFolderAccess: Sendable {
    let approveCreation: @Sendable (URL) async -> Bool
    let openProject: @Sendable (DevelopmentWorkspace) async throws -> Void

    public init(
        approveCreation: @escaping @Sendable (URL) async -> Bool,
        openProject: @escaping @Sendable (DevelopmentWorkspace) async throws -> Void
    ) {
        self.approveCreation = approveCreation
        self.openProject = openProject
    }
}
