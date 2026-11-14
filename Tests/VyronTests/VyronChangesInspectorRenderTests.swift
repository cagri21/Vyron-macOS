import AppKit
import SwiftUI
import XCTest
import VyronDevelopment
@testable import Vyron

@MainActor
final class VyronChangesInspectorRenderTests: XCTestCase {
    func testRenderHistoricalChangeInSidebarWithoutSourceFolder() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let projectPath = "/Projects/Archived"
        let conversation = Conversation(title: "Review", workspacePath: projectPath)
        let model = test.model
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.workspaceState.workspaceURL = nil
        let file = try fixture(
            path: "Sources/Workspace/Composer.swift",
            before: "struct Composer {\n    let title = \"Draft\"\n}\n",
            after: "struct Composer {\n    let title = \"Message\"\n    let isEnabled = true\n}\n"
        )
        let otherFile = try fixture(
            path: "Tests/ComposerTests.swift",
            before: nil,
            after: "import XCTest\n"
        )
        model.showChangeReview(
            conversationID: conversation.id,
            workspacePath: projectPath,
            changes: [otherFile, file],
            selectedPath: file.path
        )
        XCTAssertEqual(model.inspector.selectedReviewChange?.id, file.id)

        let size = CGSize(width: 560, height: 600)
        let content = ProjectInspector()
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
        }
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/conversation-changes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("inspector.png"), options: .atomic)
        XCTAssertTrue(containsChangeColors(bitmap), "The opened file should paint added and removed lines.")
    }

    private func fixture(path: String, before: String?, after: String) throws -> DevelopmentChange {
        var fields = ["id": UUID().uuidString, "path": path, "after": after, "unifiedDiff": ""]
        fields["before"] = before
        return try JSONDecoder().decode(DevelopmentChange.self, from: JSONEncoder().encode(fields))
    }

    private func containsChangeColors(_ bitmap: NSBitmapImageRep) -> Bool {
        var foundAddition = false
        var foundRemoval = false
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                foundAddition = foundAddition || color.greenComponent - color.redComponent > 0.35
                foundRemoval = foundRemoval || color.redComponent - color.greenComponent > 0.35
                if foundAddition && foundRemoval { return true }
            }
        }
        return false
    }
}
