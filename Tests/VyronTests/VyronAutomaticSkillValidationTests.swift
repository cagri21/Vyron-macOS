import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronAutomaticSkillValidationTests: XCTestCase {
    func testConflictingUnmanagedNameStopsSetupAndPreservesExplicitCommand() async throws {
        for name in ["vyron-pdf", "Vyron-PDF", "Vyron PDF"] {
            let library = try fixture()
            let existing = library.localDirectory.appendingPathComponent("custom-pdf")
            try library.writeSkill(
                named: name,
                at: existing,
                instructions: "Preserve the user's existing PDF workflow."
            )
            let document = existing.appendingPathComponent("SKILL.md")
            let contents = try String(contentsOf: document, encoding: .utf8)

            for prompt in ["Create a PDF", "/pdf Read this document."] {
                do {
                    _ = try await VyronSkillContextLoader.load(library.request(prompt))
                    XCTFail("A managed skill must not take over an existing unmanaged command.")
                } catch VyronSkillSetupError.nameConflict {
                    XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), contents)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
                }
            }

            let selected = try await VyronSkillContextLoader.load(library.request("/vyron-pdf Read this document."))

            XCTAssertFalse(selected.didInstallSkills)
            XCTAssertEqual(selected.commands.map(\.name), ["vyron-pdf"])
            XCTAssertEqual(selected.commands.first?.skill.fileURL, document)
            XCTAssertTrue(selected.text?.contains("Preserve the user's existing PDF workflow.") == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    func testGloballyDuplicatedCatalogAliasIsRejectedBeforeWrites() async throws {
        let library = try fixture()
        let catalog = """
        {"version":1,"skills":[
          {"identifier":"vyron-pdf","aliases":["pdf"],"terms":["pdf"],"actions":["create"]},
          {"identifier":"vyron-report","aliases":["pdf"],"terms":["report"],"actions":["create"]}
        ]}
        """
        try writeCatalog(catalog, in: library)

        XCTAssertThrowsError(try VyronSkillSetupCatalog.read(from: library.catalogDirectory))
        await assertSetupRejectedBeforeWrites(library)
    }

    func testInvalidCatalogIdentifiersAreRejectedBeforeWrites() async throws {
        let library = try fixture()
        let invalidIdentifiers = ["Vyron-pdf", "1vyron-pdf", String(repeating: "a", count: 65)]
        for identifier in invalidIdentifiers {
            let catalog = """
            {"version":1,"skills":[{
              "identifier":"\(identifier)","aliases":["pdf"],"terms":["pdf"],"actions":["create"]
            }]}
            """
            try writeCatalog(catalog, in: library)

            XCTAssertThrowsError(try VyronSkillSetupCatalog.read(from: library.catalogDirectory), identifier)
            await assertSetupRejectedBeforeWrites(library)
        }
    }

    private func fixture() throws -> VyronAutomaticSkillTestLibrary {
        let library = try VyronAutomaticSkillTestLibrary()
        addTeardownBlock { try library.cleanUp() }
        return library
    }

    private func writeCatalog(_ catalog: String, in library: VyronAutomaticSkillTestLibrary) throws {
        try catalog.write(
            to: library.catalogDirectory.appendingPathComponent("catalog.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertSetupRejectedBeforeWrites(_ library: VyronAutomaticSkillTestLibrary) async {
        do {
            _ = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))
            XCTFail("An invalid trusted catalog must fail before installation.")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }
}
