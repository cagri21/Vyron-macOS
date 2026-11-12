import Foundation
import XCTest
@testable import VyronCore
@testable import VyronDevelopment

final class VyronDevelopmentOptionalGitTests: XCTestCase, @unchecked Sendable {
    func testSimulatedMissingGitStillAllowsFileWorkAndLocalCommands() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let content = "# Local project\nFile work continues without Git.\n"
        let provider = VyronSteeringTestProvider { round, _ in
            let call: DevelopmentToolCall
            switch round {
            case 1:
                call = Self.command("./git status --short", id: "initial-git-status")
            case 2:
                call = Self.command("git diff --stat", id: "skipped-git-diff")
            case 3:
                call = DevelopmentToolCall(
                    name: "write_file",
                    arguments: ["path": .string("README.md"), "content": .string(content)],
                    id: "write-project-notes"
                )
            case 4:
                call = DevelopmentToolCall(
                    name: "read_file", arguments: ["path": .string("README.md")], id: "read-project-notes"
                )
            case 5:
                call = Self.command("/usr/bin/true", id: "local-command")
            default:
                return DevelopmentMessage(role: "assistant", content: "Created and read the project notes.")
            }
            return DevelopmentMessage(role: "assistant", toolCalls: [call])
        }

        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureCommandApproval(.fullAccess)
        let result = try await agent.run(
            goal: "Create and read README.md, then run one local command. Git is optional; do not initialize it.",
            model: "fixture-coder",
            onEvent: { events.append($0) },
            approveCommand: { _ in XCTFail("The local fixture has explicit full-access approval"); return false }
        )

        let git = try XCTUnwrap(result.commands.first)
        try VyronProtectedCommandTestSupport.requireExecutionAvailable(git)
        XCTAssertEqual(git.command, "./git status --short")
        XCTAssertEqual(git.exitCode, 128, git.output)
        XCTAssertTrue(git.output.contains("fatal: not a git repository"), git.output)
        XCTAssertEqual(result.commands.map(\.command), ["./git status --short", "/usr/bin/true"])
        XCTAssertTrue(try XCTUnwrap(result.commands.last).succeeded)
        XCTAssertEqual(events.values.filter { $0.kind == .commandStarted }.compactMap(\.command), [
            "./git status --short", "/usr/bin/true"
        ])
        XCTAssertEqual(result.changedFiles, ["README.md"])
        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(result.finalMessage.contains("repeated actions made no new progress"))
        XCTAssertEqual(
            try String(contentsOf: project.rootURL.appendingPathComponent("README.md"), encoding: .utf8), content
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent(".git").path))

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        let skipped = try XCTUnwrap(requests[2].first { $0.toolCallID == "skipped-git-diff" })
        XCTAssertTrue(skipped.content.contains("Not executed"), skipped.content)
        XCTAssertTrue(skipped.content.contains("not a successful command or verification result"), skipped.content)
        let read = try XCTUnwrap(requests[4].first { $0.toolCallID == "read-project-notes" })
        XCTAssertTrue(read.content.contains("File work continues without Git."), read.content)
        for request in requests.dropFirst() {
            assertOptionalGitGuidance(request)
        }
    }

    func testRepeatedSimulatedMissingGitSkipsReachTheStagnationGuard() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let commands = ["./git status --short", "git diff --stat", "git log -1", "git ls-files", "git show HEAD"]
        let provider = VyronSteeringTestProvider { round, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [Self.command(
                commands[min(round - 1, commands.count - 1)], id: "git-attempt-\(round)"
            )])
        }

        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureCommandApproval(.fullAccess)
        let result = try await agent.run(
            goal: "Inspect this local folder without initializing Git.", model: "fixture-coder",
            onEvent: { events.append($0) },
            approveCommand: { _ in XCTFail("The local fixture has explicit full-access approval"); return false }
        )

        let git = try XCTUnwrap(result.commands.first)
        try VyronProtectedCommandTestSupport.requireExecutionAvailable(git)
        XCTAssertEqual(git.exitCode, 128, git.output)
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(events.values.filter { $0.kind == .commandStarted }.count, 1)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.finalMessage.contains("repeated actions made no new progress"), result.finalMessage)
        let requests = await provider.recordedRequests()
        XCTAssertGreaterThan(requests.count, 1, "One newly learned capability may permit a recovery round")
        XCTAssertLessThanOrEqual(requests.count, 1 + VyronDevelopmentRunLimits.stagnantRounds)
        for request in requests.dropFirst() {
            assertOptionalGitGuidance(request)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent(".git").path))
    }

    func testNewRunRetriesSimulatedMissingGitInsteadOfPersistingCapability() async throws {
        let project = try workspace()
        let provider = VyronSteeringTestProvider { round, _ in
            round.isMultiple(of: 2)
                ? DevelopmentMessage(role: "assistant", content: "The folder has no Git repository.")
                : DevelopmentMessage(role: "assistant", toolCalls: [Self.command(
                    "./git status --short", id: "git-\(round)"
                )])
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureCommandApproval(.fullAccess)
        for _ in 0..<2 {
            let result = try await agent.run(
                goal: "Check whether Git inspection is available in this folder.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            let git = try XCTUnwrap(result.commands.first)
            try VyronProtectedCommandTestSupport.requireExecutionAvailable(git)
            XCTAssertEqual(result.commands.count, 1)
            XCTAssertEqual(git.exitCode, 128, git.output)
            XCTAssertTrue(result.isComplete)
        }

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        guard requests.count == 4 else { return }
        XCTAssertFalse(requests[0].contains { $0.content.contains("Git inspection is optional for this task") })
        XCTAssertFalse(requests[2].contains { $0.content.contains("Git inspection is optional for this task") })
        assertOptionalGitGuidance(requests[1])
        assertOptionalGitGuidance(requests[3])
    }

    func testContextLearnsMissingRepositoryExactlyOnceAndKeepsGitOptional() throws {
        var context = VyronDevelopmentGitContext()
        XCTAssertFalse(context.isUnavailable)
        XCTAssertNil(context.guidance)
        XCTAssertNil(context.skipReason(for: "git status"))

        XCTAssertTrue(context.observe(commandResult("git status")))
        XCTAssertTrue(context.isUnavailable)
        XCTAssertFalse(context.observe(commandResult("git diff --stat")))
        let guidance = try XCTUnwrap(context.guidance)
        XCTAssertTrue(guidance.contains("Git inspection is optional"))
        XCTAssertTrue(guidance.contains("required edits, and appropriate local build or test tools"))
        XCTAssertTrue(guidance.contains("Do not initialize a repository"))
        XCTAssertNotNil(context.skipReason(for: "git diff --stat"))
        XCTAssertNil(context.skipReason(for: "swift --version"))
        XCTAssertNil(context.skipReason(for: "git diff --no-index before.txt after.txt"))

        let freshRun = VyronDevelopmentGitContext()
        XCTAssertFalse(freshRun.isUnavailable)
        XCTAssertNil(freshRun.guidance)
        XCTAssertNil(freshRun.skipReason(for: "git status"))
    }

    func testSuccessOtherGitFailuresTimeoutsAndSpoofedOutputDoNotDisableGit() {
        let results = [
            commandResult("git status", exitCode: 0, output: "On branch main\nnothing to commit\n"),
            commandResult("git show missing", output: "fatal: ambiguous argument 'missing': unknown revision\n"),
            commandResult("git status", output: "fatal: detected dubious ownership in repository\n"),
            commandResult("git status", output: "fatal: not a git repository: /missing/linked-worktree\n"),
            commandResult("git status", exitCode: 1),
            commandResult("git status", timedOut: true),
            commandResult("git status", output: "warning: example text says fatal: not a git repository\n"),
            commandResult("python3 fixture.py"),
            commandResult("git init"),
            commandResult("git status && /usr/bin/true")
        ]
        for result in results {
            var context = VyronDevelopmentGitContext()
            XCTAssertFalse(context.observe(result), result.command + ": " + result.output)
            XCTAssertFalse(context.isUnavailable)
            XCTAssertNil(context.guidance)
            XCTAssertNil(context.skipReason(for: "git status"))
        }
    }

    func testGitInspectionClassificationUsesNativeParsingAndDoesNotHideRejectedCommands() throws {
        let inspections = [
            "git status --short", "/usr/bin/git status --short", "\"/usr/bin/git\" 'diff' --stat",
            "'git' 'log' -1", "git rev-parse --show-toplevel", "git ls-files"
        ]
        var context = VyronDevelopmentGitContext()
        XCTAssertTrue(context.observe(commandResult("git status")))
        for command in inspections {
            XCTAssertTrue(DevelopmentWorkspace.isGitInspectionCommand(command), command)
            XCTAssertNoThrow(try DevelopmentWorkspace.validateCommand(command), command)
            XCTAssertNotNil(context.skipReason(for: command), command)
        }
        let rejected = [
            "git init", "git push", "git reset --hard", "git -C Other status", "git -c alias.inspect=status inspect",
            "git --git-dir=Other status", "git --work-tree=Other status", "git status; /usr/bin/true", "git status | cat",
            "git status && /usr/bin/true", "git 'status", "git"
        ]
        for command in rejected {
            XCTAssertFalse(DevelopmentWorkspace.isGitInspectionCommand(command), command)
            XCTAssertNil(context.skipReason(for: command), command)
            XCTAssertThrowsError(try DevelopmentWorkspace.validateCommand(command), command)
        }
        for command in ["swift --version", "/usr/bin/true", "git diff --no-index before.txt after.txt"] {
            XCTAssertFalse(DevelopmentWorkspace.isGitInspectionCommand(command), command)
            XCTAssertNil(context.skipReason(for: command), command)
            XCTAssertNoThrow(try DevelopmentWorkspace.validateCommand(command), command)
        }
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOptionalGit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        // Runner-owned temporary folders can inherit the real project's ancestor .git.
        // This explicitly approved fixture exercises native guarded execution and emits
        // the canonical diagnostic deterministically without changing Git's environment.
        let git = root.appendingPathComponent("git")
        let script = """
        #!/bin/sh
        printf '%s\\n' 'fatal: not a git repository (or any of the parent directories): .git' >&2
        exit 128

        """
        try Data(script.utf8).write(to: git)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: git.path)
        return try DevelopmentWorkspace(rootURL: root)
    }

    private static func command(_ command: String, id: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "run_command", arguments: ["command": .string(command)], id: id)
    }

    private func commandResult(
        _ command: String,
        exitCode: Int32 = 128,
        output: String = "fatal: not a git repository (or any of the parent directories): .git\n",
        timedOut: Bool = false
    ) -> CommandResult {
        CommandResult(
            id: UUID(), command: command, exitCode: exitCode, output: output,
            timedOut: timedOut, truncated: false, duration: 0.01
        )
    }

    private func assertOptionalGitGuidance(
        _ messages: [DevelopmentMessage], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(messages.contains {
            $0.role == "system" && $0.content.contains("Git inspection is optional for this task")
                && $0.content.contains("Continue with project file inspection")
                && $0.content.contains("Do not initialize a repository")
        }, "Later inference must retain optional Git guidance without granting Git initialization", file: file, line: line)
    }
}
