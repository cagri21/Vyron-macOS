import Foundation

struct VyronCommandLaunch {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    private static let profile = """
    (version 1)
    (deny default)
    (allow file-read*)
    (deny file-read* (subpath (param "SSH")) (subpath (param "AWS")) (subpath (param "CODEX")) (subpath (param "KEYCHAINS")))
    (allow file-write* (subpath (param "PROJECT")) (subpath (param "RUN")) (literal "/dev/null"))
    (allow process-exec)
    (allow process-fork)
    (allow sysctl-read)
    (allow signal (target self))
    """

    init(_ invocation: VyronCommandInvocation) throws {
        let storage = invocation.directories.storage
        let root = invocation.directories.project
        let program = invocation.executable
        let requestedArguments = invocation.arguments
        if invocation.request.access == .fullAccess {
            executable = program
            arguments = [program] + requestedArguments
            var inherited = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let paths = (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
            let defaults = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin",
                            home + "/.local/bin"]
            inherited["PATH"] = (paths + defaults.filter { !paths.contains($0) }).joined(separator: ":")
            inherited["HOME"] = inherited["HOME"] ?? home
            inherited["GIT_TERMINAL_PROMPT"] = "0"
            inherited["NO_COLOR"] = "1"
            environment = inherited
            return
        }
        let home = storage.appendingPathComponent("home", isDirectory: true)
        let temp = storage.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: temp,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let actualHome = FileManager.default.homeDirectoryForCurrentUser.path
        var argv = [
            "/usr/bin/sandbox-exec", "-D", "PROJECT=" + root.path, "-D", "RUN=" + storage.path,
            "-D", "SSH=" + actualHome + "/.ssh", "-D", "AWS=" + actualHome + "/.aws",
            "-D", "CODEX=" + actualHome + "/.codex", "-D", "KEYCHAINS=" + actualHome + "/Library/Keychains", "-p",
            Self.profile, program
        ]
        let tool = URL(fileURLWithPath: program).lastPathComponent.lowercased()
        if tool == "git" {
            argv += [
                "-c", "credential.helper=", "-c", "protocol.allow=never", "-c", "core.fsmonitor=false", "-c",
                "core.hooksPath=/dev/null", "-c", "core.pager=cat", "-c", "maintenance.auto=false", "-c", "gc.auto=0"
            ]
        }
        var effectiveArguments = requestedArguments
        if tool == "git", ["diff", "log", "show"].contains(requestedArguments.first ?? "") {
            effectiveArguments.insert(contentsOf: ["--no-ext-diff", "--no-textconv"], at: 1)
        }
        if tool == "git", requestedArguments.starts(with: ["reflog", "show"]) {
            effectiveArguments.insert(contentsOf: ["--no-ext-diff", "--no-textconv"], at: 2)
        }
        if tool == "swift",
            ["build", "test"].contains(requestedArguments.first ?? ""), !requestedArguments.contains("--disable-sandbox") {
            // SwiftPM cannot install a nested Seatbelt profile. The enclosing
            // process still retains Vyron's network and filesystem restrictions.
            effectiveArguments.insert("--disable-sandbox", at: 1)
        }
        if tool == "swift",
            ["build", "test"].contains(requestedArguments.first ?? ""), !requestedArguments.contains("--build-system") {
            // The native engine runs locally without the Swift Build service IPC.
            effectiveArguments.insert(contentsOf: ["--build-system", "native"], at: 1)
        }
        argv += effectiveArguments
        let useExistingMessage = tool == "git" && requestedArguments.count == 2 && requestedArguments[1] == "--continue"
            && ["am", "cherry-pick", "merge", "rebase", "revert"].contains(requestedArguments[0])
        let values = [
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "HOME=" + home.path,
            "TMPDIR=" + temp.path + "/", "TMP=" + temp.path, "TEMP=" + temp.path,
            "XDG_CACHE_HOME=" + home.path + "/.cache", "LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8", "CI=1", "TERM=dumb",
            "NO_COLOR=1",
            "PIP_NO_INDEX=1", "PIP_DISABLE_PIP_VERSION_CHECK=1", "NPM_CONFIG_OFFLINE=true", "COREPACK_ENABLE_NETWORK=0",
            "CARGO_NET_OFFLINE=true", "UV_OFFLINE=1",
            "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null",
            "GIT_ASKPASS=/usr/bin/false", "GIT_SSH_COMMAND=/usr/bin/false", "GIT_OPTIONAL_LOCKS=0",
            "GIT_EDITOR=" + (useExistingMessage ? "/usr/bin/true" : "/usr/bin/false"),
            "GIT_SEQUENCE_EDITOR=/usr/bin/false"
        ]
        executable = "/usr/bin/sandbox-exec"
        arguments = argv
        environment = Dictionary(uniqueKeysWithValues: values.map { value in
            let fields = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(fields[0]), String(fields[1]))
        })
    }
}
