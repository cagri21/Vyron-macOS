public struct VyronDevelopmentFolderRequest: Sendable, Equatable {
    public let path: String
    public let openAsProject: Bool

    public init(path: String, openAsProject: Bool = false) {
        self.path = path
        self.openAsProject = openAsProject
    }
}
