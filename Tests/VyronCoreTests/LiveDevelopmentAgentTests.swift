import CryptoKit
import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

/// Opt in explicitly: VYRON_LIVE_MODEL=qwen3-coder:30b swift test --filter LiveDevelopmentAgentTests
final class LiveDevelopmentAgentTests: XCTestCase, @unchecked Sendable {
    func testActualFollowUpRunsOneNativeTestCommandWithoutEditing() async throws {
        guard let model = ProcessInfo.processInfo.environment["VYRON_LIVE_MODEL"], !model.isEmpty else {
            throw XCTSkip("Set VYRON_LIVE_MODEL to run the real local follow-up proof.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-live-followup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/LocalAgentDemo"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tests/LocalAgentDemoTests"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"LocalAgentDemo\", products: [.library(name: \"LocalAgentDemo\", targets: [\"LocalAgentDemo\"])], targets: [.target(name: \"LocalAgentDemo\"), .testTarget(name: \"LocalAgentDemoTests\", dependencies: [\"LocalAgentDemo\"])])\n",
            "Sources/LocalAgentDemo/Triple.swift": "public func triple(_ number: Int) -> Int { number * 3 }\n",
            "Tests/LocalAgentDemoTests/TripleTests.swift": "import XCTest\n@testable import LocalAgentDemo\nfinal class TripleTests: XCTestCase { func testTriple() { XCTAssertEqual(triple(4), 12) } }\n"
        ]
        for (path, content) in files { try content.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        let context: String
        if let path = ProcessInfo.processInfo.environment["VYRON_LIVE_CONTEXT_PATH"] {
            context = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        } else {
            context = "user: Fix the triple implementation and run its tests.\nassistant: Fixed multiplication by 2 to multiplication by 3. Tests now pass.\nuser: Run swift test exactly once without editing.\nassistant: The earlier response did not execute a real command."
        }
        let result = try await DevelopmentAgent(workspace: DevelopmentWorkspace(rootURL: root)).run(
            goal: "Run swift test exactly once. Do not edit any files. Report the actual exit code and result in two sentences.",
            model: model,
            automaticModelSelection: false,
            conversationContext: context,
            onEvent: { event in
                if event.kind == .commandStarted || event.kind == .commandFinished { print("[Follow-up proof] \(event.kind.rawValue): \(event.command ?? "") \(event.message)") }
            },
            approveCommand: { _ in false }
        )
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(result.commands.first?.command, "swift test")
        XCTAssertTrue(result.commands.first?.succeeded == true, result.commands.first?.output ?? result.finalMessage)
        XCTAssertTrue(result.changedFiles.isEmpty)
        for (path, content) in files { XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8), content) }
        print("[Follow-up proof] One actual native Swift test command completed with exit \(result.commands.first?.exitCode ?? -999); source, tests and manifest unchanged.")
    }

    func testActualCoderReadsRepairsImplementationAndPassesRealSwiftTests() async throws {
        guard let model = ProcessInfo.processInfo.environment["VYRON_LIVE_MODEL"], !model.isEmpty else {
            throw XCTSkip("Set VYRON_LIVE_MODEL to run the real local development-agent proof.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-live-development-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/AgentProof"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tests/AgentProofTests"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "AgentProof", products: [.library(name: "AgentProof", targets: ["AgentProof"])], targets: [.target(name: "AgentProof"), .testTarget(name: "AgentProofTests", dependencies: ["AgentProof"])])
        """
        let implementation = """
        public func sum(_ values: [Int]) -> Int {
            values.reduce(0, -)
        }
        """
        let tests = """
        import XCTest
        @testable import AgentProof
        final class NumbersTests: XCTestCase {
            func testSum() {
                XCTAssertEqual(sum([1, 2, 3, 4]), 10)
                XCTAssertEqual(sum([]), 0)
            }
        }
        """
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let sourceURL = root.appendingPathComponent("Sources/AgentProof/Numbers.swift")
        try implementation.write(to: sourceURL, atomically: true, encoding: .utf8)
        let testsURL = root.appendingPathComponent("Tests/AgentProofTests/NumbersTests.swift")
        try tests.write(to: testsURL, atomically: true, encoding: .utf8)
        let originalTestHash = SHA256.hash(data: Data(tests.utf8))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let agent = DevelopmentAgent(workspace: workspace)
        let result = try await agent.run(
            goal: "Inspect this Swift package and fix its sum implementation bug. First run swift test to observe the failure before editing. Read the implementation and test files, use edit_file to fix only Sources/AgentProof/Numbers.swift, then run swift test again to verify success. Keep all test files, test expectations and Package.swift unchanged. No dependencies or network. Report actual command results.",
            model: model,
            automaticModelSelection: false,
            onEvent: { event in
                if event.kind == .status || event.kind == .toolStarted || event.kind == .commandFinished || event.kind == .fileChanged {
                    print("[Development proof] \(event.kind.rawValue): \(event.message) \(event.command ?? event.path ?? "")")
                }
            },
            approveCommand: { _ in false }
        )
        let checks = result.commands.filter { DevelopmentAgent.isVerificationCommand($0.command) }
        XCTAssertLessThanOrEqual(checks.count, 3)
        XCTAssertTrue(checks.contains { !$0.succeeded }, "Expected actual initial failing-test feedback")
        XCTAssertTrue(checks.last?.succeeded == true, "Final real Swift test did not pass: \(checks.last?.output ?? result.finalMessage)")
        XCTAssertEqual(Set(result.changedFiles), ["Sources/AgentProof/Numbers.swift"])
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: testsURL)), originalTestHash, "The agent must fix implementation rather than weaken tests")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8), manifest)
        XCTAssertNotEqual(try String(contentsOf: sourceURL, encoding: .utf8), implementation)
        print("[Development proof] verified changed files: \(result.changedFiles), command exits: \(checks.map(\.exitCode)), steps: \(result.steps)")
    }
}
