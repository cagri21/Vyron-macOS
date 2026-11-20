import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWorkFolderAttachmentTests: XCTestCase {
    func testUltraWorkSendsEveryLargeFolderAndKeepsFollowUpWithinBudget() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkFolderAttachmentTestProvider()
        let model = "gpt-6.2-sol"
        test.select(test.profile(modelName: model), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.effort = .ultra

        let names = ["First Reference", "Second Reference", "Third Reference", "Last Reference"]
        let folders = try names.map { name in
            try writeFolder(named: name, in: test.directory)
        }
        let prompt = "Compare the attached projects' architecture and concurrency examples. Keep the project read-only."
        test.model.composer.draft = prompt
        test.model.importFolderAttachments(folders)
        try await test.waitUntil { !test.model.composerAttachments.isImporting }

        let imported = test.model.composerAttachments.folderAttachmentDraft.folders
        XCTAssertEqual(imported.map(\.name), names)
        XCTAssertGreaterThan(imported.reduce(0) { $0 + $1.context.utf8.count }, 24_000)
        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.requests
        let requestedModels = await provider.requestedModels
        let requestedEfforts = await provider.requestedEfforts
        XCTAssertNil(test.model.errorMessage)
        XCTAssertEqual(requestedModels, [model])
        XCTAssertEqual(requestedEfforts, [.ultra])
        let content = try XCTUnwrap(requests.first).map(\.content).joined(separator: "\n")
        XCTAssertTrue(content.contains(prompt))
        for name in names {
            XCTAssertTrue(content.contains("Attached folder: \(String(reflecting: name))"))
            XCTAssertTrue(content.contains("\(name) opening excerpt."))
            XCTAssertTrue(content.contains("\(name) closing excerpt."))
        }
        for folder in imported {
            XCTAssertTrue(content.contains(folder.context), "Work received a partial snapshot for \(folder.name)")
        }
        XCTAssertEqual(test.model.messages.first { $0.conversationRole == .user }?.content, prompt)
        XCTAssertTrue(test.model.composerAttachments.folderAttachmentDraft.folders.isEmpty)

        let followUp = "Review this implementation brief.\n"
            + String(repeating: "Check the project concurrency examples.\n", count: 2_600)
        test.model.composer.draft = followUp
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let followUpRequests = await provider.requests
        XCTAssertEqual(followUpRequests.count, 2)
        let followUpMessages = try XCTUnwrap(followUpRequests.last)
        XCTAssertTrue(followUpMessages.contains { $0.content.contains(followUp) })
        let encodedBytes = try JSONEncoder().encode(followUpMessages).count
        XCTAssertLessThan(encodedBytes, provider.developmentMessageBudget(for: model).maximumBytes)
        XCTAssertNil(test.model.errorMessage)
    }

    private func writeFolder(named name: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filler = String(repeating: "Local project reference details.\n", count: 105)
        try ("\(name) opening excerpt.\n" + filler).write(
            to: folder.appendingPathComponent("Architecture.md"), atomically: true, encoding: .utf8
        )
        try (filler + "\(name) closing excerpt.\n").write(
            to: folder.appendingPathComponent("Concurrency.md"), atomically: true, encoding: .utf8
        )
        return folder
    }
}
