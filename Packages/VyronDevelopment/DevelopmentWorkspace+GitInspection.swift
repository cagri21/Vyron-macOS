import Foundation

extension DevelopmentWorkspace {
    public nonisolated static func isGitCommand(_ command: String) -> Bool {
        gitArguments(command) != nil
    }

    public nonisolated static func isGitInitializationCommand(_ command: String) -> Bool {
        gitArguments(command)?.first == "init"
    }

    /// Classification shares execution's parser and policy; it never authorizes or executes a command.
    public nonisolated static func isGitInspectionCommand(_ command: String) -> Bool {
        guard let arguments = gitArguments(command), VyronGitCommandPolicy.isInspection(arguments),
            arguments.first != "--version" else { return false }
        // Comparing two files without an index does not require repository discovery.
        return arguments.first != "diff" || !arguments.dropFirst().prefix(while: { $0 != "--" }).contains("--no-index")
    }

    private nonisolated static func gitArguments(_ command: String) -> [String]? {
        do {
            let arguments = try CommandPolicy.arguments(command)
            guard URL(fileURLWithPath: arguments[0]).lastPathComponent.lowercased() == "git" else {
                return nil
            }
            try CommandPolicy.validate(arguments)
            return Array(arguments.dropFirst())
        } catch {
            // Invalid syntax and refused commands remain failures of normal execution, never optional Git skips.
            return nil
        }
    }
}
