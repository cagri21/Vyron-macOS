import Foundation
import XCTest
@testable import VyronDevelopment

final class VyronFullAccessCommandTests: XCTestCase, @unchecked Sendable {
    func testFullAccessCanWriteTheRequestedOutsideDestinationAndUseLoopback() async throws {
        let root = try fixture()
        let outside = try fixture().appendingPathComponent("release-proof.txt")
        let script = """
        from pathlib import Path
        import os
        import socket
        import sys
        import threading

        destination = Path(sys.argv[1])
        destination.write_text('new installer fixture')
        assert destination.read_text() == 'new installer fixture'
        server = socket.socket()
        server.bind(('127.0.0.1', 0))
        server.listen(1)
        server.settimeout(3)
        def respond():
            connection, _ = server.accept()
            with connection:
                assert connection.recv(64) == b'release-check'
                connection.sendall(b'published-fixture')
        thread = threading.Thread(target=respond)
        thread.start()
        with socket.create_connection(server.getsockname(), timeout=3) as connection:
            connection.sendall(b'release-check')
            assert connection.recv(64) == b'published-fixture'
        thread.join(timeout=3)
        assert not thread.is_alive()
        server.close()
        assert os.environ['HOME'] == sys.argv[2]
        print('outside-write-and-network-verified')
        """
        try script.write(to: root.appendingPathComponent("release.py"), atomically: true, encoding: .utf8)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let request = VyronCommandRequest(
            command: "python3 release.py \(quoted(outside.path)) \(quoted(home))",
            access: .fullAccess,
            approved: true
        )

        let result = try await DevelopmentWorkspace(rootURL: root).runCommand(request) { _ in }

        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertTrue(result.output.contains("outside-write-and-network-verified"), result.output)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "new installer fixture")
    }

    func testFullAccessRequiresCapturedApprovalAndPreservesCommandSyntaxValidation() async throws {
        let workspace = try DevelopmentWorkspace(rootURL: fixture())
        do {
            _ = try await workspace.runCommand(VyronCommandRequest(command: "/usr/bin/true", access: .fullAccess)) { _ in }
            XCTFail("Unapproved full access must not execute a command.")
        } catch is DevelopmentError {}
        for command in ["swift build; echo bypass", "swift build | cat", "echo ready &"] {
            XCTAssertThrowsError(try DevelopmentWorkspace.validateCommand(command, access: .fullAccess))
        }
        for command in ["curl --version", "git push", "zsh scripts/build-app.sh release", "npm publish"] {
            XCTAssertThrowsError(try DevelopmentWorkspace.validateCommand(command))
            XCTAssertNoThrow(try DevelopmentWorkspace.validateCommand(command, access: .fullAccess))
        }
    }

    func testFullAccessCancellationStopsTheCommandGroup() async throws {
        let root = try fixture()
        let marker = root.appendingPathComponent("late-write.txt")
        let script = """
        import subprocess
        import sys
        import time
        child = "from pathlib import Path; import time; time.sleep(0.7); Path('late-write.txt').write_text('late')"
        subprocess.Popen([sys.executable, '-c', child])
        print('ready-to-cancel', flush=True)
        time.sleep(30)
        """
        try script.write(to: root.appendingPathComponent("cancel.py"), atomically: true, encoding: .utf8)
        let ready = expectation(description: "Command and child started")
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let request = VyronCommandRequest(command: "python3 cancel.py", access: .fullAccess, approved: true)
        let task = Task {
            try await workspace.runCommand(request) { chunk in
                if chunk.contains("ready-to-cancel") { ready.fulfill() }
            }
        }
        await fulfillment(of: [ready], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled commands must throw cancellation.")
        } catch is CancellationError {}
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let next = try await workspace.runCommand(
            VyronCommandRequest(command: "/usr/bin/true", access: .fullAccess, approved: true)
        ) { _ in }
        XCTAssertTrue(next.succeeded, next.output)
    }

    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronFullAccess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
