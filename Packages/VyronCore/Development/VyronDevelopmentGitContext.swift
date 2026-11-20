import Foundation
import VyronDevelopment

/// A per-run capability learned from actual command evidence, independent of task completion or global settings.
struct VyronDevelopmentGitContext {
    private(set) var isUnavailable = false

    var guidance: String? {
        guard isUnavailable else { return nil }
        return """
        The selected project folder is not a Git repository. Git inspection is optional for this task and is \
        unavailable until the folder is initialized. Continue with project file inspection, required edits, and \
        appropriate local build or test tools. Do not initialize a repository unless the user explicitly requests it. \
        Once initialization succeeds, Git inspection can resume.
        """
    }

    func skipReason(for command: String) -> String? {
        guard isUnavailable, DevelopmentWorkspace.isGitInspectionCommand(command) else { return nil }
        return """
        Not executed: Git inspection was previously detected as unavailable because the selected project folder \
        is not a Git repository. Continue the task using project files and appropriate local build or test tools. \
        This skipped inspection is not a successful command or verification result.
        """
    }

    /// Returns true once, when a real read-only Git result establishes that repository inspection is unavailable.
    mutating func observe(_ result: CommandResult) -> Bool {
        if isUnavailable, result.succeeded, DevelopmentWorkspace.isGitInitializationCommand(result.command) {
            isUnavailable = false
            return false
        }
        guard !isUnavailable, result.exitCode == 128, !result.timedOut,
            DevelopmentWorkspace.isGitInspectionCommand(result.command),
            result.output.split(whereSeparator: \.isNewline).contains(where: { line in
                let diagnostic = line.trimmingCharacters(in: .whitespaces)
                return diagnostic == "fatal: not a git repository"
                    || diagnostic.hasPrefix("fatal: not a git repository (")
            })
        else { return false }
        isUnavailable = true
        return true
    }
}
