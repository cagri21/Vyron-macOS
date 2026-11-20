import VyronLocalization

enum VyronGitCommandPolicy {
    private static let inspectionCommands: Set<String> = [
        "cat-file", "check-ignore", "describe", "diff", "for-each-ref", "grep", "log", "ls-files",
        "ls-tree", "merge-base", "rev-list", "rev-parse", "shortlog", "show", "status"
    ]
    private static let localCommands: Set<String> = [
        "add", "am", "apply", "bisect", "blame", "branch", "checkout", "cherry-pick", "commit", "init", "merge", "mv",
        "notes", "rebase", "reset", "restore", "revert", "rm", "stash", "switch", "tag", "worktree"
    ]
    private static let identityKeys: Set<String> = ["user.name", "user.email"]
    private static let identityVariables: Set<String> = ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"]

    static func validate(_ arguments: [String]) throws {
        guard let action = arguments.first else {
            throw DevelopmentError(VyronProjectApprovalText.gitCommandRequired)
        }
        let options = commandOptions(arguments)
        if isInspection(arguments) {
            if options.contains(where: { isInspectionSideEffect($0, action: action) }) {
                throw DevelopmentError(VyronProjectApprovalText.gitInspectionSideEffects)
            }
            return
        }
        if action == "config", isIdentityWrite(arguments) { return }
        guard localCommands.contains(action) else {
            throw DevelopmentError(VyronProjectApprovalText.gitCommandUnavailable)
        }
        if action == "reset", options.contains(where: { matchesLongOption($0, "--hard") }) {
            throw DevelopmentError(VyronProjectApprovalText.gitHardResetUnavailable)
        }
        if (action == "bisect" && arguments.dropFirst().first(where: { $0 != "--" }) == "run")
            || (action == "rebase" && options.contains(where: isScriptedRebase)) {
            throw DevelopmentError(VyronProjectApprovalText.gitInteractiveCommandUnavailable)
        }
    }

    static func isInspection(_ arguments: [String]) -> Bool {
        guard let action = arguments.first else { return false }
        if inspectionCommands.contains(action) { return true }
        let operands = Array(arguments.dropFirst())
        switch action {
        case "--version":
            return operands.isEmpty
        case "config":
            return (operands.count == 2 && operands[0] == "--local" && identityKeys.contains(operands[1]))
                || (operands.count == 3 && operands[0] == "--local" && operands[1] == "--get"
                    && identityKeys.contains(operands[2]))
        case "reflog":
            return operands.isEmpty || operands.first == "show" || operands.first == "exists"
        case "remote":
            return operands.isEmpty
        case "var":
            return operands.count == 1 && identityVariables.contains(operands[0])
        default:
            return false
        }
    }

    private static func isIdentityWrite(_ arguments: [String]) -> Bool {
        arguments.count == 4 && arguments[1] == "--local" && identityKeys.contains(arguments[2])
            && !arguments[3].hasPrefix("-")
    }

    private static func commandOptions(_ arguments: [String]) -> ArraySlice<String> {
        arguments.dropFirst().prefix { $0 != "--" }
    }

    private static func isInspectionSideEffect(_ argument: String, action: String) -> Bool {
        if action == "cat-file", matchesLongOption(argument, "--filters") { return true }
        if action == "grep", matchesLongOption(argument, "--open-files-in-pager")
            || (argument.hasPrefix("-") && !argument.hasPrefix("--") && argument.dropFirst().contains("O")) {
            return true
        }
        if argument == "--text", ["diff", "grep", "log", "reflog", "show"].contains(action) { return false }
        return ["--output", "--ext-diff", "--textconv"].contains { matchesLongOption(argument, $0) }
    }

    private static func isScriptedRebase(_ argument: String) -> Bool {
        if argument.hasPrefix("--") {
            return matchesLongOption(argument, "--interactive") || matchesLongOption(argument, "--exec")
        }
        return argument.hasPrefix("-") && !argument.hasPrefix("-C")
            && argument.dropFirst().contains(where: { $0 == "i" || $0 == "x" })
    }

    private static func matchesLongOption(_ argument: String, _ option: String) -> Bool {
        guard argument.hasPrefix("--"), argument.count > 2 else { return false }
        let name = argument.prefix { $0 != "=" }
        return option.hasPrefix(name)
    }
}
