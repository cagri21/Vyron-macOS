import Foundation

public struct VyronScheduledTaskContext: Codable, Equatable, Sendable {
    public var workspacePath: String?
    public var projectPath: String?
    public var mode: VyronScheduledTaskMode
    public var model: VyronScheduledModelSelection

    public init(
        workspacePath: String?,
        mode: VyronScheduledTaskMode,
        model: VyronScheduledModelSelection,
        projectPath: String? = nil
    ) {
        self.workspacePath = workspacePath
        self.projectPath = projectPath
        self.mode = mode
        self.model = model
    }
}
