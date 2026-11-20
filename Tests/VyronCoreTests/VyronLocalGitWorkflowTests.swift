import Foundation
import XCTest
import VyronDevelopment
import VyronLocalization
@testable import VyronCore

@MainActor
final class VyronLocalGitWorkflowTests: XCTestCase {
    func testLocalGitCommandsRetainExistingApprovalClassification() throws {
        let reads = [
            "git status --short", "git diff --text", "git reflog show", "git var GIT_AUTHOR_IDENT",
            "git config --local --get user.name", "git remote"
        ]
        let writes = [
            "git init", "git add -- README.md", "git commit -m 'Test commit'", "git switch -c topic",
            "git apply --cached changes.patch", "git rebase main", "git reset --soft HEAD~1",
            "git config --local user.email fixture@example.invalid", "git stash", "git tag v1"
        ]
        for command in reads {
            XCTAssertNoThrow(try DevelopmentWorkspace.validateCommand(command), command)
            XCTAssertNil(DevelopmentWorkspace.approvalRequirement(command: command), command)
        }
        for command in writes {
            XCTAssertNoThrow(try DevelopmentWorkspace.validateCommand(command), command)
            XCTAssertEqual(
                DevelopmentWorkspace.approvalRequirement(command: command),
                VyronProjectApprovalText.commandMayChangeProjectFiles, command
            )
        }
        XCTAssertFalse(DevelopmentAgent.isVerificationCommand("git commit -m unittest"))
    }

    func testNetworkUnsafeOptionsAndGitEnvironmentOverridesStayBlocked() {
        let commands = [
            "git clone https://example.invalid/test", "git push", "git pull", "git fetch", "git remote -v",
            "git remote show origin",
            "git -C Other status", "git -c core.hooksPath=hooks commit -m test", "git config --global user.name Fixture",
            "git config --local user.name --list", "git clean -fd", "git reset --hard", "git reset --har",
            "git diff --output=patch.txt", "git log --ext-diff", "git grep -nO match",
            "git cat-file --filters HEAD:README.md", "git cat-file --text HEAD:README.md",
            "git rebase --exec 'touch unsafe'", "git rebase -i main", "git rebase --ex=unsafe", "git bisect run ./build.sh",
            "git reset '--har\0'"
        ]
        for command in commands {
            XCTAssertThrowsError(try DevelopmentWorkspace.validateCommand(command), command)
        }
    }

    func testDefaultWorkModeReviewsGitAddAndDoesNotStageWhenDeclined() async throws {
        let workspace = try workspace()
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let command = "git add -- README.md"
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 1 {
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "run_command", arguments: ["command": .string(command)]
                )])
            }
            return DevelopmentMessage(role: "assistant", content: "Staging was declined.")
        }
        let result = try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: "Stage README.md.", model: "fixture-coder", onEvent: { _ in },
            approveCommand: { review in
                reviews.append(review)
                return false
            }
        )
        XCTAssertEqual(reviews.values.map(\.command), [command])
        XCTAssertTrue(result.commands.isEmpty)
    }

    func testTrustedCommandNameCannotHideAGitWriteBehindAnAlias() async throws {
        let workspace = try workspace()
        let alias = workspace.rootURL.appendingPathComponent("xcodebuild")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: URL(fileURLWithPath: "/usr/bin/git"))
        do {
            _ = try await workspace.runCommand("./xcodebuild add -- README.md") { _ in }
            XCTFail("The resolved executable requires review.")
        } catch let error as DevelopmentError {
            XCTAssertTrue(error.message.contains("Review commands"))
        }
    }

    func testGuardedGitStagesOnlyTheRequestedFileAndCommitsIt() async throws {
        let workspace = try workspace()
        try Data("release notes\n".utf8).write(to: workspace.rootURL.appendingPathComponent("README.md"))
        try Data("unrelated draft\n".utf8).write(to: workspace.rootURL.appendingPathComponent("draft.txt"))
        let commands = [
            "git init -b main",
            "git config --local user.name 'Vyron Fixture'",
            "git config --local user.email fixture@example.invalid",
            "git add -- README.md",
            "git diff --cached --name-only",
            "git commit -m 'docs: add release notes'",
            "git log -1 --format=%s --name-only",
            "git status --short"
        ]
        var results: [CommandResult] = []
        for command in commands {
            let approved = DevelopmentWorkspace.approvalRequirement(command: command) != nil
            let result = try await workspace.runCommand(command, approved: approved) { _ in }
            try VyronProtectedCommandTestSupport.requireExecutionAvailable(result)
            XCTAssertTrue(result.succeeded, "\(command): \(result.output)")
            guard result.succeeded else { return }
            results.append(result)
        }
        XCTAssertEqual(results[4].output.trimmingCharacters(in: .whitespacesAndNewlines), "README.md")
        XCTAssertEqual(results[6].output.split(whereSeparator: \.isNewline), ["docs: add release notes", "README.md"])
        XCTAssertEqual(results[7].output.trimmingCharacters(in: .whitespacesAndNewlines), "?? draft.txt")
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronLocalGit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }
}
