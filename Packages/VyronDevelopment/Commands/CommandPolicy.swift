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

    static func validate(_ argv: [String], access: VyronCommandAccess = .restricted) throws {
        guard let program = argv.first, !program.isEmpty else {
            throw DevelopmentError("Enter an executable and its arguments.")
        }
        if access == .fullAccess { return }
        let name = URL(fileURLWithPath: program).lastPathComponent.lowercased()
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

    static func approvalRequirement(command: String, access: VyronCommandAccess = .restricted) -> String? {
        guard let argv = try? arguments(command), (try? validate(argv, access: access)) != nil else {
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

    static func executable(
        _ program: String,
        arguments: [String],
        root: URL,
        access: VyronCommandAccess = .restricted
    ) throws -> String {
        let directTools: [String: String] = [
            "swift": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
            "python3": "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        ]
        if access == .restricted, let direct = directTools[
            program.hasPrefix("/usr/bin/") ? URL(fileURLWithPath: program).lastPathComponent : program
        ], FileManager.default.isExecutableFile(atPath: direct) {
            try validate([URL(fileURLWithPath: direct).lastPathComponent] + arguments, access: access)
            return direct
        }
        var searchPaths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
        if access == .fullAccess {
            let configuredPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .map(String.init)
            searchPaths = configuredPaths + searchPaths.filter { !configuredPaths.contains($0) }
            searchPaths.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path)
        }
        let paths =
            program.contains("/")
            ? [program.hasPrefix("/") ? program : root.appendingPathComponent(program).path]
            : searchPaths.map {
                $0 + "/" + program
            }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw DevelopmentError("This executable is not installed locally: \(program)")
        }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        try validate([URL(fileURLWithPath: canonical).lastPathComponent] + arguments, access: access)
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
