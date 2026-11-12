import Foundation
import XCTest
@testable import VyronCore
@testable import VyronDevelopment

final class VyronDevelopmentFolderLocationTests: XCTestCase, @unchecked Sendable {
    func testMissingMoveDoesNotCreateDestinationOrChangeTheInferenceRoot() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("Desktop/RequestedProject", isDirectory: true)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = scripted([
            Self.folder(destination.path), Self.openFolder(destination.path),
            Self.folder(destination.path, open: true), Self.write("# Current project\n")
        ])
        let agent = try await configuredAgent(provider, project: project, opened: opened)

        let result = try await run(agent, events: events, goal: "Move this conversation to the requested folder.")

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertTrue(events.values.contains { $0.failure?.contains("does not exist") == true })
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertFalse(exists(destination.deletingLastPathComponent()))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Current project\n")
        let requests = await provider.recordedRequests()
        XCTAssertGreaterThanOrEqual(requests.count, 2)
        for request in requests {
            XCTAssertTrue(Self.systemText(request).contains(project.rootURL.path))
            XCTAssertFalse(Self.systemText(request).contains(destination.path))
        }
    }

    func testLibraryLookupRejectsFolderCreationAndMoveAndContinuesReading() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
        let note = "Current project reference."
        try Data(note.utf8).write(to: project.rootURL.appendingPathComponent("reference.txt"))
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = scripted([
            Self.folder("Library"), Self.openFolder(library.path),
            DevelopmentToolCall(name: "read_file", arguments: ["path": .string("reference.txt")])
        ])
        let agent = try await configuredAgent(provider, project: project, opened: opened)

        _ = try await run(agent, events: events, goal: "Can you find the reference in the Library folder and open it?")

        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("Library")))
        XCTAssertEqual(events.values.filter { $0.failure?.contains("read-only tools") == true }.count, 2)
        let requests = await provider.recordedRequests()
        XCTAssertTrue(requests.last?.contains { $0.role == "tool" && $0.content.contains(note) } == true)
    }

    func testFolderRemovedDuringReviewIsNotRecreatedAfterConfirmation() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("Vanished", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try await configuredAgent(scripted([
            Self.openFolder(destination.path), Self.folder(destination.path), Self.write("# Still current\n")
        ]), project: project, opened: opened)

        _ = try await run(agent, events: events, goal: "Move this conversation to the requested folder.") { approval in
            XCTAssertEqual(approval.action, .moveConversation)
            do {
                try FileManager.default.removeItem(at: destination)
                return true
            } catch {
                XCTFail("Could not remove the fixture folder: \(error)")
                return false
            }
        }

        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertFalse(exists(destination))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Still current\n")
        XCTAssertTrue(events.values.contains { $0.failure?.contains("changed during review") == true })
    }

    func testRepeatedBareCurrentNameDoesNotCreateNestedProjectWithOmittedOrTrueFlag() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let name = project.rootURL.lastPathComponent
        let agent = try await configuredAgent(scripted([
            Self.folder(name), Self.folder(name, open: true), Self.write("# Current project\n")
        ]), project: project, opened: opened)

        let result = try await run(agent, events: events)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(events.values.contains { $0.failure != nil })
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent(name, isDirectory: true)))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Current project\n")
    }

    func testOrdinaryRelativeSubfolderDoesNotAdoptItAsAProject() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try await configuredAgent(scripted([
            Self.folder("Models"), Self.write("# Original project\n")
        ]), project: project, opened: opened)

        let result = try await run(agent, events: events)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(events.values.contains { $0.failure != nil })
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertTrue(exists(project.rootURL.appendingPathComponent("Models", isDirectory: true)))
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("Models/README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Original project\n")
    }

    func testOmittingFlagCreatesExternalFolderAndKeepsOriginalProject() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("OnlyCreateThisFolder", isDirectory: true)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try await configuredAgent(scripted([
            Self.folder(destination.path), Self.write("# Still original\n")
        ]), project: project, opened: opened)

        let result = try await run(agent, events: events)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(events.values.contains { $0.failure != nil })
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertTrue(exists(destination))
        XCTAssertFalse(exists(destination.appendingPathComponent("README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Still original\n")
    }

    func testExplicitFalseAllowsSameNamedSourceSubfolder() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let name = project.rootURL.lastPathComponent
        let agent = try await configuredAgent(scripted([
            Self.folder(name, open: false), Self.write("# Root notes\n")
        ]), project: project, opened: opened)

        let result = try await run(agent, events: events)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(events.values.contains { $0.failure != nil })
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertTrue(exists(project.rootURL.appendingPathComponent(name, isDirectory: true)))
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent(name + "/README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "# Root notes\n")
    }

    func testLaterRunKeepsAdoptedRootAndReopeningItsNameDoesNotNestFolders() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("RequestedProject", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                return DevelopmentMessage(role: "assistant", toolCalls: [Self.openFolder(destination.path)])
            case 3:
                return DevelopmentMessage(role: "assistant", toolCalls: [Self.openFolder(destination.lastPathComponent)])
            case 4:
                return DevelopmentMessage(role: "assistant", toolCalls: [Self.write("# Follow-up notes\n")])
            default:
                return DevelopmentMessage(role: "assistant", content: "The requested action is finished.")
            }
        }
        let agent = try await configuredAgent(provider, project: project, opened: opened)
        let conversationID = UUID()
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID, responseID: UUID()
        ))

        let first = try await agent.run(
            goal: "Move this conversation to the requested folder.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { $0.action == .moveConversation }
        )
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID, responseID: UUID()
        ))
        let followUp = try await agent.run(
            goal: "Add follow-up notes inside the same project.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertTrue(first.isComplete, first.finalMessage)
        XCTAssertTrue(followUp.isComplete, followUp.finalMessage)
        XCTAssertFalse(events.values.contains { $0.failure != nil })
        XCTAssertEqual(opened.values.map { $0.rootURL.path }, [destination.path])
        XCTAssertEqual(try text(destination.appendingPathComponent("README.md")), "# Follow-up notes\n")
        XCTAssertFalse(exists(destination.appendingPathComponent(destination.lastPathComponent, isDirectory: true)))
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent(destination.lastPathComponent, isDirectory: true)))
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("README.md")))
        let requests = await provider.recordedRequests()
        XCTAssertGreaterThanOrEqual(requests.count, 5)
        for request in requests.dropFirst() {
            XCTAssertTrue(Self.systemText(request).contains(destination.path))
            XCTAssertFalse(Self.systemText(request).contains(project.rootURL.path))
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFolderLocation-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func workspace(in root: URL) throws -> DevelopmentWorkspace {
        let url = root.appendingPathComponent("Current", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return try DevelopmentWorkspace(rootURL: url)
    }

    private func configuredAgent(
        _ provider: VyronSteeringTestProvider,
        project: DevelopmentWorkspace,
        opened: VyronSteeringTestLog<DevelopmentWorkspace>
    ) async throws -> DevelopmentAgent {
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in true }, openProject: { opened.append($0) }
        ))
        return agent
    }

    private func scripted(_ calls: [DevelopmentToolCall]) -> VyronSteeringTestProvider {
        VyronSteeringTestProvider { round, _ in
            round <= calls.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "The requested notes are saved.")
        }
    }

    private static func folder(_ path: String, open: Bool? = nil) -> DevelopmentToolCall {
        var arguments: [String: DevelopmentJSONValue] = ["path": .string(path)]
        if let open { arguments["open_as_project"] = .bool(open) }
        return DevelopmentToolCall(name: "create_folder", arguments: arguments)
    }

    private static func openFolder(_ path: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "open_project_folder", arguments: ["path": .string(path)])
    }

    private static func write(_ content: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("README.md"), "content": .string(content)
        ])
    }

    private static func systemText(_ messages: [DevelopmentMessage]) -> String {
        messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
    }

    private func run(
        _ agent: DevelopmentAgent,
        events: VyronSteeringTestLog<DevelopmentEvent>,
        goal: String = "Create the requested folder and its notes.",
        approveMove: @escaping @Sendable (CommandApproval) async -> Bool = { _ in
            XCTFail("Unexpected approval request.")
            return false
        }
    ) async throws -> DevelopmentResult {
        try await agent.run(
            goal: goal, model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: approveMove
        )
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}
