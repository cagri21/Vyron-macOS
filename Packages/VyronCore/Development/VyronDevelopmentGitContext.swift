import Foundation
import VyronDevelopment

/// A per-run capability learned from actual command evidence, independent of task completion or global settings.
struct VyronDevelopmentGitContext {
    private(set) var isUnavailable = false

    var guidance: String? {
        guard isUnavailable else { return nil }
        return """
        The selected project folder is not a Git repository. Git inspection is optional for this task and is \
        unavailable for this run. Do not repeat Git inspection commands. Continue with project file inspection, \
        required edits, and appropriate local build or test tools. Do not initialize a repository merely to \
        unblock this task: that requires explicit user authorization, and the current project command tools \
        support read-only Git inspection only. Preserve all other task, command, and verification requirements.
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
