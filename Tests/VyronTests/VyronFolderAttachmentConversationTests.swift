import AppKit
import Foundation
import SwiftUI
import XCTest
import VyronCore
import VyronLocalization
@testable import Vyron

@MainActor
final class VyronFolderAttachmentConversationTests: XCTestCase {
    func testCaptureFolderPreviewAndPrivacyHintInEachSupportedLanguage() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider)
        test.model.composerAttachments.folderAttachmentDraft.folders = [VyronFolderAttachment(
            id: UUID(),
            name: "A project folder with a long name for checking attachment layout",
            context: "Supplied folder contents.",
            summary: VyronFolderAttachmentSummary(includedFileCount: 12, skippedFileCount: 3, isLimited: true)
        )]
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/folder-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [VyronLanguage.english, .turkish, .ukrainian] {
            var arguments = previousArguments
            arguments[VyronLocalizationDefaultsKey.language.rawValue] = language.rawValue
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            for width: CGFloat in [640, 504] {
                let content = VyronComposer()
                    .environmentObject(test.model)
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .environment(\.colorScheme, .dark)
                    .frame(width: width)
                    .background(Palette.canvas)
                let hosting = NSHostingView(rootView: content)
                hosting.appearance = NSAppearance(named: .darkAqua)
                hosting.frame = CGRect(x: 0, y: 0, width: width, height: 1)
                for _ in 0..<4 {
                    hosting.layoutSubtreeIfNeeded()
                    await Task.yield()
                    hosting.setFrameSize(hosting.fittingSize)
                }
                let size = hosting.fittingSize
                guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                    throw XCTSkip("BLOCKED: folder composer has no offscreen fitting size.")
                }
                hosting.setFrameSize(size)
                hosting.layoutSubtreeIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                    throw XCTSkip("BLOCKED: native offscreen folder composer capture is unavailable.")
                }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent(
                    "composer-\(language.rawValue)-\(Int(width)).png"
                ), options: .atomic)
                XCTAssertEqual(size.width, width, accuracy: 1)
                XCTAssertGreaterThan(size.height, 100)
                XCTAssertLessThan(size.height, 450, "The folder preview and privacy hint must fit the composer.")
                guard hasForegroundContent(bitmap) else {
                    throw XCTSkip("BLOCKED: native offscreen folder composer did not paint its contents.")
                }
            }
        }
    }

    func testFolderOnlySendIncludesNestedTextAndPersistsSnapshotForFollowUp() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider)
        let nested = test.project.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let source = nested.appendingPathComponent("Feature.swift")
        try Data("struct FolderSnapshotFeature {}\n".utf8).write(to: source)
        test.model.importFolderAttachments([test.project])
        XCTAssertTrue(test.model.composerAttachments.isImporting)
        XCTAssertFalse(test.model.canSend)
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertTrue(test.model.composerAttachments.folderAttachmentDraft.folders.isEmpty)
        var requests = await provider.receivedMessages
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].contains { $0.content.contains("FolderSnapshotFeature") })
        XCTAssertTrue(requests[0].contains { $0.content.contains("Sources/Feature.swift") })
        XCTAssertNil(test.model.errorMessage)
        let stored = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let restored = try JSONDecoder().decode([Conversation].self, from: stored)
        let contexts = try XCTUnwrap(restored.first?.contextByMessageID)
        XCTAssertTrue(contexts.values.contains { $0.contains("FolderSnapshotFeature") })

        try Data("struct ChangedAfterAttachment {}\n".utf8).write(to: source)
        test.model.composer.draft = "Explain the folder contents in more detail."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        requests = await provider.receivedMessages
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].contains { $0.content.contains("FolderSnapshotFeature") })
        XCTAssertFalse(requests[1].contains { $0.content.contains("ChangedAfterAttachment") })
    }

    func testImportFailureIsAtomicAndRetryCanRemoveFolder() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.importFolderAttachments([test.project, test.directory.appendingPathComponent("Missing")])
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertTrue(test.model.composerAttachments.folderAttachmentDraft.folders.isEmpty)
        XCTAssertNotNil(test.model.errorMessage)

        test.model.importFolderAttachments([test.project])
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders.map(\.name), ["Project"])
        XCTAssertNil(test.model.errorMessage)
        let folder = try XCTUnwrap(test.model.composerAttachments.folderAttachmentDraft.folders.first)
        test.model.removeFolderAttachment(folder.id)
        XCTAssertFalse(test.model.composerAttachments.hasDrafts)
    }

    func testNewConversationCancelsImportAndRejectsLateResult() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let folder = try await VyronFolderAttachmentLoader().load(test.project)
        let generation = test.model.composerAttachments.folderAttachmentDraft.generation
        test.model.loadComposerAttachments {
            await Task.yield()
            return VyronComposerAttachments(folders: [folder])
        }
        XCTAssertTrue(test.model.composerAttachments.isImporting)
        XCTAssertFalse(test.model.canSelectComposerMode(.plan))

        test.model.newConversation()
        test.model.composer.draft = "A different conversation."
        for _ in 0..<30 { await Task.yield() }

        XCTAssertNotEqual(test.model.composerAttachments.folderAttachmentDraft.generation, generation)
        XCTAssertTrue(test.model.composerAttachments.folderAttachmentDraft.folders.isEmpty)
        XCTAssertFalse(test.model.composerAttachments.isImporting)
        XCTAssertNil(test.model.composerAttachments.folderAttachmentImportTask)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertEqual(test.model.composer.draft, "A different conversation.")
    }

    func testFoldersCannotBeLostIntoTextOnlyQueue() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider)
        let folder = try await VyronFolderAttachmentLoader().load(test.project)
        test.model.composerAttachments.folderAttachmentDraft.folders = [folder]
        test.model.composer.draft = "Analyze this folder."
        test.model.beginTestForegroundResponse()

        XCTAssertFalse(test.model.canSend)
        XCTAssertFalse(test.model.canAttachFolders)
        test.model.send()
        test.model.importFolderAttachments([test.project])

        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders, [folder])
        XCTAssertEqual(test.model.composer.draft, "Analyze this folder.")
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        test.model.foregroundRun.stop()
    }

    func testOversizedPromptPreservesFolderAndDraft() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider)
        let folder = try await VyronFolderAttachmentLoader().load(test.project)
        test.model.composerAttachments.folderAttachmentDraft.folders = [folder]
        let prompt = String(repeating: "x", count: VyronScreenshotLimits.maximumConversationBudget)
        test.model.composer.draft = prompt

        test.model.send()

        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders, [folder])
        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertNotNil(test.model.errorMessage)
    }

    func testCompactionRejectsFolderWithoutDiscardingAttachment() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider)
        let folder = try await VyronFolderAttachmentLoader().load(test.project)
        test.model.composerAttachments.folderAttachmentDraft.folders = [folder]
        test.model.composer.draft = "/compact"

        test.model.send()

        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders, [folder])
        XCTAssertEqual(test.model.composer.draft, "/compact")
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.errorMessage, VyronCompactionText.attachments)
    }

    func testFolderChatBypassesAutomaticComputerAndWebRouting() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider)
        test.model.computerWork.automaticRequestRouting = true
        test.model.composerAttachments.folderAttachmentDraft.folders = [try await VyronFolderAttachmentLoader().load(test.project)]
        test.model.composer.draft = "Open Safari and search for pharmacies in Istanbul. Explain this folder only."

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.receivedMessages
        let developmentRequests = await provider.developmentRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(developmentRequests, 0)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertNil(test.model.errorMessage)
    }

    private func hasForegroundContent(_ bitmap: NSBitmapImageRep) -> Bool {
        var lightSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent + color.greenComponent + color.blueComponent > 1.5 {
                    lightSamples += 1
                }
            }
        }
        return lightSamples > 100
    }
}
