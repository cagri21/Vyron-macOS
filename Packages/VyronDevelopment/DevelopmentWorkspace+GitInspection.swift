import Foundation

extension DevelopmentWorkspace {
    /// Classification shares execution's parser and policy; it never authorizes or executes a command.
    public nonisolated static func isGitInspectionCommand(_ command: String) -> Bool {
        do {
            let arguments = try CommandPolicy.arguments(command)
            try CommandPolicy.validate(arguments)
            guard URL(fileURLWithPath: arguments[0]).lastPathComponent.lowercased() == "git" else {
                return false
            }
            // Comparing two files without an index does not require repository discovery.
            if arguments[1] == "diff", arguments.dropFirst(2).contains("--no-index") { return false }
            // Git context must refer to the selected folder, rather than another working tree or configuration.
            let contextOptions = ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]
            return !arguments.dropFirst().contains { argument in
                contextOptions.contains { option in
                    argument == option || argument.hasPrefix(option + "=")
                }
            }
        } catch {
            // Invalid syntax and refused commands remain failures of normal execution, never optional Git skips.
            return false
        }
    }
}
