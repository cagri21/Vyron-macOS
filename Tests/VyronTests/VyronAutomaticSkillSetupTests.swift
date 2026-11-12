import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronAutomaticSkillSetupTests: XCTestCase {
    func testWorkRequestInstallsPortableSkillAndLoadsItsInstructions() async throws {
        let library = try fixture()
        let context = try await VyronSkillContextLoader.load(library.request("Read report.pdf and extract its text."))

        XCTAssertTrue(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
        XCTAssertTrue(context.text?.contains("Use Vyron's portable PDF workflow.") == true)
        XCTAssertTrue(context.catalog.contains { $0.name == "vyron-pdf" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.installedDirectory.path))
    }

    func testSecondRequestPreservesEditedManagedSkill() async throws {
        let library = try fixture()
        _ = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))
        try library.writeSkill(
            named: "vyron-pdf",
            at: library.installedDirectory,
            instructions: "Keep this customized PDF workflow."
        )

        let context = try await VyronSkillContextLoader.load(library.request("Update the PDF report."))

        XCTAssertFalse(context.didInstallSkills)
        XCTAssertTrue(context.text?.contains("Keep this customized PDF workflow.") == true)
        let contents = try String(
            contentsOf: library.installedDirectory.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("Keep this customized PDF workflow."))
    }

    func testExplicitCuratedAliasInstallsAndLoadsSkill() async throws {
        let library = try fixture()

        let context = try await VyronSkillContextLoader.load(library.request("/pdf Read the attached file."))

        XCTAssertTrue(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
        XCTAssertTrue(context.text?.contains("portable PDF workflow") == true)
    }

    func testDirectPoliteCreationRequestInstallsSkill() async throws {
        let library = try fixture()

        let context = try await VyronSkillContextLoader.load(library.request("Can you create a PDF report?"))

        XCTAssertTrue(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
    }

    func testArtifactAboutAnAppStillUsesSkill() async throws {
        for prompt in ["Create a PDF report about this Swift app.", "Create a PDF guide for Vyron."] {
            let library = try fixture()

            let context = try await VyronSkillContextLoader.load(library.request(prompt))

            XCTAssertTrue(context.didInstallSkills, prompt)
            XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"], prompt)
        }
    }

    func testNegativeStyleConstraintDoesNotBlockArtifactCreation() async throws {
        let library = try fixture()

        let context = try await VyronSkillContextLoader.load(library.request("Create a PDF without images"))

        XCTAssertTrue(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
    }

    func testPlainPromptUsesPortableSkillInsteadOfUnrelatedHostSkill() async throws {
        let library = try fixture()
        try library.writeSkill(
            named: "pdf:pdf",
            at: library.localDirectory.appendingPathComponent("host-pdf"),
            instructions: "This workflow requires a private host runtime."
        )

        let context = try await VyronSkillContextLoader.load(library.request("Create a PDF document."))

        XCTAssertTrue(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
        XCTAssertTrue(context.text?.contains("portable PDF workflow") == true)
        XCTAssertFalse(context.text?.contains("private host runtime") == true)
    }

    func testExplicitExistingHostCommandRetainsItsOwnInstructions() async throws {
        let library = try fixture()
        try library.writeSkill(
            named: "pdf:pdf",
            at: library.localDirectory.appendingPathComponent("host-pdf"),
            instructions: "Explicitly selected host workflow."
        )

        for enabled in [true, false] {
            let context = try await VyronSkillContextLoader.load(
                library.request("/pdf:pdf Read the document.", enabled: enabled)
            )

            XCTAssertFalse(context.didInstallSkills)
            XCTAssertEqual(context.commands.map(\.name), ["pdf:pdf"])
            XCTAssertTrue(context.text?.contains("Explicitly selected host workflow.") == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    func testDisablingSetupKeepsPlainPromptFastPath() async throws {
        let library = try fixture()

        let context = try await VyronSkillContextLoader.load(library.request("Create a PDF report.", enabled: false))

        XCTAssertNil(context.text)
        XCTAssertTrue(context.commands.isEmpty)
        XCTAssertFalse(context.didInstallSkills)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
    }

    func testReadOnlyModesDoNotAutoSelectOrInstallForPlainPrompt() async throws {
        let library = try fixture()

        for mode in [VyronSkillSetupMode.plan, .chat] {
            let context = try await VyronSkillContextLoader.load(
                library.request("Create a PDF report.", mode: mode)
            )

            XCTAssertNil(context.text)
            XCTAssertTrue(context.commands.isEmpty)
            XCTAssertFalse(context.didInstallSkills)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    func testPlanCanExplicitlyReuseInstalledManagedSkillWithoutWrites() async throws {
        let library = try fixture()
        _ = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))

        let context = try await VyronSkillContextLoader.load(
            library.request("/vyron-pdf Review the PDF plan.", mode: .plan)
        )

        XCTAssertFalse(context.didInstallSkills)
        XCTAssertEqual(context.commands.map(\.name), ["vyron-pdf"])
        XCTAssertTrue(context.text?.contains("portable PDF workflow") == true)
    }

    private func fixture() throws -> VyronAutomaticSkillTestLibrary {
        let library = try VyronAutomaticSkillTestLibrary()
        addTeardownBlock { try library.cleanUp() }
        return library
    }
}
