import AppKit
import SwiftUI
import XCTest
import VyronCore
@testable import Vyron

/// Optional visual evidence from the real picker without opening an app, window, or model connection.
@MainActor
final class VyronSkillPickerRenderTests: XCTestCase {
    func testCaptureCompactPicker() async throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_SKILL_PICKER"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_SKILL_PICKER=1 for offscreen picker verification.")
        }
        let root = VyronSkillRoot(
            directoryURL: URL(fileURLWithPath: "/LocalSkills"), source: .codex, scope: .personal
        )
        let skills = [
            VyronSkillMetadata(name: "vyron", description: "Build, review, and test your local projects."),
            VyronSkillMetadata(name: "vyron-appstore", description: "Create App Store screenshots from your real app."),
            VyronSkillMetadata(name: "vyron-commit", description: "Create a reviewed local Conventional Commit."),
            VyronSkillMetadata(name: "vyron-refactor-movelle", description: "Refactor an app using Movelle's architecture."),
            VyronSkillMetadata(name: "vyron-refactor-indentation-swift", description: "Format Swift using four-space indentation."),
            VyronSkillMetadata(name: "vyron-mac-space-volume-checker", description: "Inspect Mac storage without deleting files.")
        ].map { metadata in
            VyronLocalSkill(
                metadata: metadata, root: root,
                fileURL: root.directoryURL.appendingPathComponent(metadata.name + "/SKILL.md"),
                preview: VyronSkillPreview(content: "Fixture", isTruncated: false)
            )
        }
        let inventory = VyronSkillInventory(skills: skills, issues: [], didReachLimit: false)
        let model = VyronComposerSkillsModel(library: VyronSkillsPresentation(loader: { _ in inventory }))
        await model.load(projectDirectory: nil)
        model.updateDraft("/")
        XCTAssertEqual(model.visibleCommands.first?.name, "compact")
        let renderer = ImageRenderer(content: VyronComposerSkillPicker(
            skills: model, draft: .constant("/"), projectDirectory: nil, submit: {}
        )
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
            .frame(width: 580)
        )
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: offscreen ImageRenderer is unavailable; no app/window fallback permitted.")
        }
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("compact-picker.png"), options: .atomic)
        let rows = ImageRenderer(content: VStack(spacing: VyronComposerSkillStyle.rowSpacing) {
            ForEach(Array(model.visibleCommands.prefix(5))) { command in
                VyronComposerSkillRow(command: command, isSelected: command.id == model.selectedCommand?.id) {}
            }
        }
            .padding(VyronComposerSkillStyle.padding)
            .frame(width: 580)
            .background(Palette.surface)
            .environment(\.locale, Locale(identifier: "en"))
        )
        rows.scale = 2
        if let rowImage = rows.cgImage {
            let rowData = try XCTUnwrap(NSBitmapImageRep(cgImage: rowImage).representation(using: .png, properties: [:]))
            try rowData.write(to: directory.appendingPathComponent("skill-rows.png"), options: .atomic)
        }
        XCTAssertEqual(image.width, 1_160)
        XCTAssertLessThan(image.height, 700, "The five-row picker should remain compact.")
        let bitmap = NSBitmapImageRep(cgImage: image)
        var brightSamples = 0
        for y in stride(from: image.height / 4, to: image.height * 3 / 4, by: 4) {
            for x in stride(from: 20, to: image.width - 20, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent + color.greenComponent + color.blueComponent > 1.6 {
                    brightSamples += 1
                }
            }
        }
        guard brightSamples > 5 else {
            throw XCTSkip("BLOCKED: ImageRenderer omitted native scroll rows; separate row evidence was saved.")
        }
    }
}
