import Darwin
import Foundation
import VyronLocalization

enum CommandPolicy {
    private static let denied: Set<String> = [
        "curl", "wget", "ssh", "scp", "sftp", "rsync", "ftp", "nc", "ncat", "netcat", "socat", "telnet", "gh", "glab",
        "npx", "sudo", "doas", "rm", "rmdir", "mv", "dd", "chmod", "chown", "chflags", "diskutil", "launchctl",
        "osascript", "open", "security", "defaults", "sh", "bash", "zsh", "fish", "env", "eval", "kill", "killall",
        "pkill"
    ]

    static func arguments(_ command: String) throws -> [String] {
        guard !command.isEmpty, command.utf8.count <= 8_000 else { throw DevelopmentError("Use a command under 8 KB.") }
        guard !command.utf8.contains(0) else { throw DevelopmentError(VyronProjectApprovalText.commandNotPermitted) }
        var arguments: [String] = [], token = "", quote: Character?, escaped = false, started = false
        for character in command {
            if escaped { token.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; started = true; continue }
            if let current = quote {
                if character == current { quote = nil } else { token.append(character) }
                started = true
                continue
            }
            if character == "'" || character == "\"" { quote = character; started = true; continue }
            if character == "\n" || character == "\r" || ";|&<>`".contains(character) {
                throw DevelopmentError(
                    "Shell operators, redirects, pipelines and background commands are unsupported. Run one executable with arguments."
                )
            }
            if character.isWhitespace {
                if started { arguments.append(token); token = ""; started = false }
            } else {
                token.append(character); started = true
            }
        }
        guard quote == nil, !escaped else {
            throw DevelopmentError("The command contains an unfinished quote or escape.")
        }
        if started { arguments.append(token) }
        guard let first = arguments.first, !first.isEmpty else {
            throw DevelopmentError("Enter an executable and its arguments.")
        }
        return arguments
    }

    static func validate(_ argv: [String]) throws {
        let name = URL(fileURLWithPath: argv[0]).lastPathComponent.lowercased()
        guard !denied.contains(name), !name.hasPrefix("git-remote-") else {
            throw DevelopmentError("Network, destructive and system-control commands are unavailable in project mode.")
        }
        if name == "git" {
            try VyronGitCommandPolicy.validate(Array(argv.dropFirst()))
        }
        if ["npm", "pnpm", "yarn", "pip", "pip3", "uv", "brew", "gem", "cargo"].contains(name),
            argv.dropFirst().contains(where: {
                [
                    "install", "add", "update", "upgrade", "publish", "login", "fetch", "download", "search",
                    "outdated", "audit", "exec", "dlx"
                ].contains($0)
            }) {
            throw DevelopmentError("Dependency downloads and remote registry operations are unavailable.")
        }
        if name == "swift",
            argv.dropFirst().contains(where: { ["resolve", "update", "fetch", "add-dependency"].contains($0) }) {
            throw DevelopmentError("Dependency resolution and downloads are unavailable offline.")
        }
        if name == "xcodebuild",
            argv.contains(where: {
                [
                    "-resolvePackageDependencies", "-downloadPlatform", "-downloadAllPlatforms",
                    "-allowProvisioningUpdates"
                ].contains($0)
            }) {
            throw DevelopmentError(
                "Downloading SDKs, resolving remote packages and updating signing credentials are unavailable."
            )
        }
    }

    static func approvalRequirement(command: String) -> String? {
        guard let argv = try? arguments(command), (try? validate(argv)) != nil else {
            return VyronProjectApprovalText.commandNotPermitted
        }
        let name = URL(fileURLWithPath: argv[0]).lastPathComponent
        let action = argv.dropFirst().first ?? ""
        if name == "swift", ["build", "test", "--version"].contains(action) { return nil }
        if name == "xcodebuild", !argv.contains("archive"), !argv.contains("-exportArchive") { return nil }
        if ["python", "python3"].contains(name), argv.count >= 3, argv[1] == "-m", argv[2] == "unittest" { return nil }
        if name.lowercased() == "git", VyronGitCommandPolicy.isInspection(Array(argv.dropFirst())) { return nil }
        return VyronProjectApprovalText.commandMayChangeProjectFiles
    }

    static func executable(_ program: String, arguments: [String], root: URL) throws -> String {
        let directTools: [String: String] = [
            "swift": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
            "python3": "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        ]
        if let direct = directTools[
            program.hasPrefix("/usr/bin/") ? URL(fileURLWithPath: program).lastPathComponent : program
        ], FileManager.default.isExecutableFile(atPath: direct) {
            try validate([URL(fileURLWithPath: direct).lastPathComponent] + arguments)
            return direct
        }
        let paths =
            program.contains("/")
            ? [program.hasPrefix("/") ? program : root.appendingPathComponent(program).path]
            : ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"].map {
                $0 + "/" + program
            }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DevelopmentError("This executable is not installed locally: \(program)")
        }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        try validate([URL(fileURLWithPath: canonical).lastPathComponent] + arguments)
        return canonical
    }

    static func isTrustedDevelopmentTool(_ path: String, requested program: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard name == URL(fileURLWithPath: program).lastPathComponent else { return false }
        return [
            "/usr/bin/swift", "/usr/bin/xcodebuild", "/usr/bin/git", "/usr/bin/python3", "/usr/bin/python",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        ].contains(path)
    }
}

final class CommandState: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var stopped = false
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func started(_ value: pid_t) {
        lock.withLock {
            pid = value
            if cancelled { _ = Darwin.kill(-pid, SIGKILL) }
        }
    }
    func cancel() {
        lock.withLock {
            cancelled = true
            if pid > 0, !stopped { _ = Darwin.kill(-pid, SIGKILL) }
        }
    }
    func kill() { lock.withLock { if pid > 0, !stopped { _ = Darwin.kill(-pid, SIGKILL) } } }
    func complete() { lock.withLock { stopped = true } }
}

enum GuardedCommand {
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

    static func run(
        command: String,
        executable: String,
        arguments: [String],
        root: URL,
        storage: URL,
        timeout: TimeInterval,
        state: CommandState,
        onOutput: @escaping @Sendable (String) -> Void
    ) throws -> CommandResult {
        if state.isCancelled { throw CancellationError() }
        let started = ProcessInfo.processInfo.systemUptime
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
            profile, executable
        ]
        let tool = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if tool == "git" {
            argv += [
                "-c", "credential.helper=", "-c", "protocol.allow=never", "-c", "core.fsmonitor=false", "-c",
                "core.hooksPath=/dev/null", "-c", "core.pager=cat", "-c", "maintenance.auto=false", "-c", "gc.auto=0"
            ]
        }
        var effectiveArguments = arguments
        if tool == "git", ["diff", "log", "show"].contains(arguments.first ?? "") {
            effectiveArguments.insert(contentsOf: ["--no-ext-diff", "--no-textconv"], at: 1)
        }
        if tool == "git", arguments.starts(with: ["reflog", "show"]) {
            effectiveArguments.insert(contentsOf: ["--no-ext-diff", "--no-textconv"], at: 2)
        }
        if tool == "swift",
            ["build", "test"].contains(arguments.first ?? ""), !arguments.contains("--disable-sandbox") {
            // SwiftPM cannot install a nested Seatbelt profile. The enclosing
            // process still retains Vyron's network and filesystem restrictions.
            effectiveArguments.insert("--disable-sandbox", at: 1)
        }
        if tool == "swift",
            ["build", "test"].contains(arguments.first ?? ""), !arguments.contains("--build-system") {
            // The native engine runs locally without the Swift Build service IPC.
            effectiveArguments.insert(contentsOf: ["--build-system", "native"], at: 1)
        }
        argv += effectiveArguments
        let useExistingMessage = tool == "git" && arguments.count == 2 && arguments[1] == "--continue"
            && ["am", "cherry-pick", "merge", "rebase", "revert"].contains(arguments[0])
        let environment = [
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
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw DevelopmentError("Could not create command output storage.") }
        defer { close(descriptors[0]); close(descriptors[1]) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        posix_spawn_file_actions_addclose(&actions, descriptors[1])
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, root.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, root.path)
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let cargv = argv.map { strdup($0) } + [nil]
        let cenv = environment.map { strdup($0) } + [nil]
        defer { for pointer in cargv + cenv { if let pointer { free(pointer) } } }
        var pid: pid_t = 0
        let error = cargv.withUnsafeBufferPointer { args in
            cenv.withUnsafeBufferPointer { env in
                posix_spawn(&pid, "/usr/bin/sandbox-exec", &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard error == 0 else { throw DevelopmentError("The protected command could not start (error \(error)).") }
        state.started(pid)
        close(descriptors[1]); descriptors[1] = -1
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        var output = Data(), buffer = [UInt8](repeating: 0, count: 8_192)
        var status: Int32 = 0, ended = false, eof = false, timedOut = false, truncated = false
        defer { state.kill(); state.complete() }
        while !ended || !eof {
            if state.isCancelled || ProcessInfo.processInfo.systemUptime - started >= timeout {
                timedOut = !state.isCancelled
                state.kill()
                if !ended { _ = waitpid(pid, &status, 0); ended = true }
                break
            }
            var poller = pollfd(fd: descriptors[0], events: Int16(POLLIN | POLLHUP), revents: 0)
            _ = poll(&poller, 1, 50)
            if poller.revents != 0 {
                let count = read(descriptors[0], &buffer, buffer.count)
                if count > 0 {
                    let room = max(0, 65_536 - output.count)
                    let accepted = min(room, count)
                    if accepted > 0 {
                        let chunk = Data(buffer.prefix(accepted)); output.append(chunk)
                        onOutput(String(decoding: chunk, as: UTF8.self))
                    }
                    truncated = truncated || count > room
                } else if count == 0 {
                    eof = true
                }
            }
            if !ended, waitpid(pid, &status, WNOHANG) == pid { ended = true }
        }
        state.kill(); state.complete()
        if state.isCancelled { throw CancellationError() }
        let exitCode: Int32 = timedOut ? 124 : ((status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F))
        let result = CommandResult(
            id: UUID(),
            command: command,
            exitCode: exitCode,
            output: String(decoding: output, as: UTF8.self),
            timedOut: timedOut,
            truncated: truncated,
            duration: ProcessInfo.processInfo.systemUptime - started
        )
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: storage.appendingPathComponent("result.json"), options: .atomic)
        }
        return result
    }
}
