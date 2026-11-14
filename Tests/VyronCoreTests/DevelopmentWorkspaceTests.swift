import Foundation
import XCTest
@testable import VyronDevelopment

final class DevelopmentWorkspaceTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-development-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testReadBeforeWriteConcurrentChangeAndRevertPreserveUserWork() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try "original\n".write(to: file, atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        do { _ = try await workspace.writeFile(path: "Main.swift", content: "unsafe"); XCTFail("Unread overwrite") } catch {}
        _ = try await workspace.readFile(path: "Main.swift")
        try "user edit\n".write(to: file, atomically: true, encoding: .utf8)
        do { _ = try await workspace.writeFile(path: "Main.swift", content: "stale"); XCTFail("Stale overwrite") } catch {}
        _ = try await workspace.readFile(path: "Main.swift")
        let change = try await workspace.writeFile(path: "Main.swift", content: "agent edit\n")
        XCTAssertEqual(change.before, "user edit\n")
        XCTAssertTrue(change.unifiedDiff.contains("-user edit"))
        try "another user edit\n".write(to: file, atomically: true, encoding: .utf8)
        do { try await workspace.revert(path: "Main.swift"); XCTFail("Revert overwrote user work") } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "another user edit\n")
    }

    func testPreviewCannotRefreshStaleEditingPermission() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try "original source\n".write(to: file, atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.readFile(path: "Main.swift")
        try "user edited source\n".write(to: file, atomically: true, encoding: .utf8)
        let preview = try await workspace.readFile(path: "Main.swift", forEditing: false)
        XCTAssertEqual(preview, "user edited source\n")
        do { _ = try await workspace.writeFile(path: "Main.swift", content: "stale agent replacement"); XCTFail("Preview refreshed stale write permission") } catch {}
        do { _ = try await workspace.editFile(path: "Main.swift", oldText: "user edited", newText: "agent"); XCTFail("Preview refreshed stale exact-edit permission") } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "user edited source\n")
    }

    func testNewTaskScopeClearsReadsButPreservesChangesAndRevert() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try "original source\n".write(to: file, atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.readFile(path: "Main.swift")
        _ = try await workspace.writeFile(path: "Main.swift", content: "agent edit\n")
        await workspace.beginTaskReadScope()
        let changes = await workspace.changes()
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.before, "original source\n")
        do { _ = try await workspace.writeFile(path: "Main.swift", content: "new task guessed source"); XCTFail("A prior task authorized a new task's overwrite") } catch {}
        do { _ = try await workspace.editFile(path: "Main.swift", oldText: "agent", newText: "next agent"); XCTFail("A prior task authorized a new task's exact edit") } catch {}
        try await workspace.revert(path: "Main.swift")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original source\n")
    }

    func testReopeningWorkspaceRestoresChangesAndRevertWithoutReadPermission() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try "original source\n".write(to: file, atomically: true, encoding: .utf8)
        let first = try DevelopmentWorkspace(rootURL: root)
        _ = try await first.readFile(path: "Main.swift")
        let written = try await first.writeFile(path: "Main.swift", content: "agent edit\n")
        let reopened = try DevelopmentWorkspace(rootURL: root)
        let restored = await reopened.changes()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, written.id)
        XCTAssertEqual(restored.first?.before, "original source\n")
        XCTAssertEqual(restored.first?.after, "agent edit\n")
        XCTAssertEqual(restored.first?.unifiedDiff, written.unifiedDiff)
        do { _ = try await reopened.writeFile(path: "Main.swift", content: "unread replacement"); XCTFail("Restored history granted edit permission") } catch {}
        try await reopened.revert(path: "Main.swift")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original source\n")
        let third = try DevelopmentWorkspace(rootURL: root)
        let empty = await third.changes()
        XCTAssertTrue(empty.isEmpty)
    }

    func testReopenedRevertPreservesExternalUserEdits() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try "original\n".write(to: file, atomically: true, encoding: .utf8)
        let first = try DevelopmentWorkspace(rootURL: root)
        _ = try await first.readFile(path: "Main.swift")
        _ = try await first.writeFile(path: "Main.swift", content: "agent\n")
        try "user changed it\n".write(to: file, atomically: true, encoding: .utf8)
        let reopened = try DevelopmentWorkspace(rootURL: root)
        do { try await reopened.revert(path: "Main.swift"); XCTFail("Reopened revert overwrote user changes") } catch {}
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "user changed it\n")
    }

    func testNewFileMultipleEditsRevertRemovesOnlyAgentFile() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.writeFile(path: "Sources/New.swift", content: "first")
        _ = try await workspace.writeFile(path: "Sources/New.swift", content: "second")
        let changes = await workspace.changes()
        XCTAssertNil(changes.first?.before)
        try await workspace.revert(path: "Sources/New.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/New.swift").path))
    }

    func testResponseUndoPreservesEarlierEditsAndRemovesNewFiles() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Main.swift")
        try Data("original\n".utf8).write(to: file)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.readFile(path: "Main.swift")
        _ = try await workspace.writeFile(path: "Main.swift", content: "earlier response\n")
        let responseChange = try await workspace.editResponseFile(
            path: "Main.swift", oldText: "earlier response", newText: "latest response"
        )
        let first = try await workspace.writeResponseFile(path: "New.swift", content: "first")
        let latest = try await workspace.writeResponseFile(path: "New.swift", content: "latest")
        let created = VyronDevelopmentResponseChanges.merging(first: first, latest: latest)
        XCTAssertNil(created.before)
        XCTAssertEqual(responseChange.before, "earlier response\n")

        let result = try await workspace.undoResponseChanges([responseChange, created])
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.restoredPaths, ["Main.swift", "New.swift"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("New.swift").path))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "earlier response\n")
        let reopened = try DevelopmentWorkspace(rootURL: root)
        let changes = await reopened.changes()
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.before, "original\n")
        XCTAssertEqual(changes.first?.after, "earlier response\n")
    }

    func testResponseUndoChecksAllFilesBeforeOverwritingAny() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let first = try await workspace.writeResponseFile(path: "First.swift", content: "first")
        let second = try await workspace.writeResponseFile(path: "Second.swift", content: "second")
        let secondFile = root.appendingPathComponent("Second.swift")
        try Data("user edit".utf8).write(to: secondFile)

        do {
            _ = try await workspace.undoResponseChanges([first, second])
            XCTFail("Undo proceeded after an external edit")
        } catch {
            XCTAssertEqual(try String(contentsOf: secondFile, encoding: .utf8), "user edit")
            let firstFile = root.appendingPathComponent("First.swift")
            XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "first")
        }
    }

    func testTruncatedReadCannotAuthorizeOverwriteButUniqueEditPreservesUnseenText() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Long.swift")
        let original = "let answer = 1\n" + String(repeating: "// unseen source\n", count: 100)
        try original.write(to: file, atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.readFile(path: "Long.swift", maxBytes: 30)
        do { _ = try await workspace.writeFile(path: "Long.swift", content: "partial"); XCTFail("Truncated overwrite") } catch {}
        _ = try await workspace.editFile(path: "Long.swift", oldText: "let answer = 1", newText: "let answer = 2")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original.replacingOccurrences(of: "answer = 1", with: "answer = 2"))
        try await workspace.revert(path: "Long.swift")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
    }

    func testSymlinksSecretsAndTraversalCannotEscapeProject() async throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try "protected".write(to: outside.appendingPathComponent("Protected.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Link.swift"), withDestinationURL: outside.appendingPathComponent("Protected.swift"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        for path in ["../Protected.swift", "Linked/Protected.swift", "Link.swift", ".env", ".git/config", "secrets.json"] {
            do { _ = try await workspace.writeFile(path: path, content: "changed"); XCTFail("Unsafe write \(path)") } catch {}
        }
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("Protected.swift"), encoding: .utf8), "protected")
    }

    func testCommandPolicyRejectsRemoteDestructiveAndShellOperators() {
        XCTAssertNil(DevelopmentWorkspace.approvalRequirement(command: "swift build"))
        XCTAssertNil(DevelopmentWorkspace.approvalRequirement(command: "python3 -m unittest discover"))
        XCTAssertNil(DevelopmentWorkspace.approvalRequirement(command: "git diff --stat"))
        for command in ["curl https://example.com", "git push", "rm -rf Sources", "swift build; echo done", "swift build | cat", "npm install", "python3 -c 'print(1)'"] {
            XCTAssertNotNil(DevelopmentWorkspace.approvalRequirement(command: command), command)
        }
    }

    func testGitAliasCannotBypassReadOnlyArguments() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("inspect-tool")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: URL(fileURLWithPath: "/usr/bin/git"))
        XCTAssertThrowsError(try CommandPolicy.executable("./inspect-tool", arguments: ["push"], root: root))
        XCTAssertEqual(try CommandPolicy.executable("./inspect-tool", arguments: ["status"], root: root), "/usr/bin/git")
    }

    func testGuardedCommandTimeoutAndOutput() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let result = try await workspace.runCommand("python3 -c 'import time; print(123, flush=True); time.sleep(5)'", timeout: 0.5, approved: true) { _ in }
        XCTAssertTrue(result.timedOut, result.output)
        XCTAssertEqual(result.exitCode, 124)
        XCTAssertTrue(result.output.contains("123"), result.output)
        XCTAssertLessThan(result.duration, 3)
    }

    func testGuardDeniesOutsideWritesAndLoopbackSockets() async throws {
        let root = try fixture(), outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let protected = outside.appendingPathComponent("protected.txt")
        try "unchanged".write(to: protected, atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let literal = String(data: try encoder.encode(protected.path), encoding: .utf8)!
        let script = """
        from pathlib import Path
        import socket
        try:
            Path(\(literal)).write_text('changed')
            raise SystemExit('outside write unexpectedly allowed')
        except PermissionError:
            print('outside-denied')
        try:
            sock = socket.socket()
            sock.bind(('127.0.0.1', 0))
            raise SystemExit('socket unexpectedly allowed')
        except PermissionError:
            print('network-denied')
        """
        try script.write(to: root.appendingPathComponent("guard_check.py"), atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let result = try await workspace.runCommand("python3 guard_check.py", approved: true) { _ in }
        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertTrue(result.output.contains("outside-denied"), result.output)
        XCTAssertTrue(result.output.contains("network-denied"), result.output)
        XCTAssertEqual(try String(contentsOf: protected, encoding: .utf8), "unchanged")
    }

    func testCancellationStopsTheProcessGroupAndItsChild() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try "import time\nfrom pathlib import Path\ntime.sleep(1.5)\nPath('late-marker').write_text('child survived')\n".write(to: root.appendingPathComponent("child.py"), atomically: true, encoding: .utf8)
        try "import subprocess,sys,time\nsubprocess.Popen([sys.executable,'child.py'])\nprint('ready',flush=True)\ntime.sleep(10)\n".write(to: root.appendingPathComponent("parent.py"), atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let (output, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            return try await workspace.runCommand("python3 parent.py", approved: true) { text in
                if text.contains("ready") { continuation.yield(()) }
            }
        }
        for await _ in output { task.cancel(); break }
        do { _ = try await task.value; XCTFail("Expected command cancellation") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("late-marker").path))
    }

    func testCancelledActorWriteDoesNotCreateSourceFile() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate { break }
            return try await workspace.writeFile(path: "Cancelled.swift", content: "should not be written")
        }
        task.cancel()
        continuation.finish()
        do { _ = try await task.value; XCTFail("Expected cancelled write refusal") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Cancelled.swift").path))
    }

    func testActualOfflineSwiftPackageBuildInsideGuard() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "GuardedExample", targets: [.target(name: "GuardedExample"), .testTarget(name: "GuardedExampleTests", dependencies: ["GuardedExample"])])
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let sources = root.appendingPathComponent("Sources/GuardedExample")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "public func answer() -> Int { 42 }\n".write(to: sources.appendingPathComponent("Answer.swift"), atomically: true, encoding: .utf8)
        let tests = root.appendingPathComponent("Tests/GuardedExampleTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "import XCTest\n@testable import GuardedExample\nfinal class AnswerTests: XCTestCase { func testAnswer() { XCTAssertEqual(answer(), 42) } }\n".write(to: tests.appendingPathComponent("AnswerTests.swift"), atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let result = try await workspace.runCommand("swift build", timeout: 90) { _ in }
        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertTrue(result.output.contains("Build complete"), result.output)
        let tested = try await workspace.runCommand("swift test", timeout: 90) { _ in }
        XCTAssertTrue(tested.succeeded, tested.output)
        XCTAssertTrue(tested.output.contains("Executed 1 test"), tested.output)
    }
}
