import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronAutomaticSkillFailureTests: XCTestCase {
    func testIncidentalCapabilityMentionDoesNotInstallSkill() async throws {
        let library = try fixture()

        let prompts = [
            "Why is PDF popular?",
            "Explain PDF compression.",
            "Read the PdfController.swift source file.",
            "Can Vyron create PDF files?",
            "Add PDF creation support to this Swift app",
            "Do not create a PDF; update README",
            "I will create a PDF tomorrow"
        ]
        for prompt in prompts {
            let context = try await VyronSkillContextLoader.load(library.request(prompt))

            XCTAssertNil(context.text, prompt)
            XCTAssertTrue(context.commands.isEmpty, prompt)
            XCTAssertFalse(context.didInstallSkills, prompt)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path), prompt)
        }
    }

    func testUnknownExplicitCommandRemainsVisibleFailure() async throws {
        let library = try fixture()

        do {
            _ = try await VyronSkillContextLoader.load(library.request("/unreviewed-pdf Read this file."))
            XCTFail("An unknown selected skill must remain a visible error.")
        } catch VyronSkillContextError.unavailable {
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    func testReadOnlyModesDoNotInstallExplicitMissingAlias() async throws {
        let library = try fixture()

        for mode in [VyronSkillSetupMode.plan, .chat] {
            do {
                _ = try await VyronSkillContextLoader.load(library.request("/pdf Read this file.", mode: mode))
                XCTFail("Read-only preflight must not install a missing selected skill.")
            } catch VyronSkillContextError.unavailable {
                XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
            }
        }
    }

    func testMissingPackageFailsBeforeContextAndCanRetryAfterRepair() async throws {
        let library = try fixture()
        try FileManager.default.removeItem(at: library.packageDirectory)

        do {
            _ = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))
            XCTFail("A missing bundled package must not silently drop required instructions.")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installedDirectory.path))
        }

        try library.writeSkill(
            named: "vyron-pdf",
            at: library.packageDirectory,
            instructions: "Recovered PDF workflow."
        )
        let recovered = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))

        XCTAssertTrue(recovered.didInstallSkills)
        XCTAssertTrue(recovered.text?.contains("Recovered PDF workflow.") == true)
    }

    func testMalformedCatalogFailsWithoutInstallingAnything() async throws {
        let library = try fixture()
        try "{invalid catalog".write(
            to: library.catalogDirectory.appendingPathComponent("catalog.json"),
            atomically: true,
            encoding: .utf8
        )

        do {
            _ = try await VyronSkillContextLoader.load(library.request("Create a PDF report."))
            XCTFail("A malformed trusted catalog must not be treated as successful setup.")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    func testCancellationDoesNotInstallOrReturnInstructions() async throws {
        let library = try fixture()
        let request = library.request("Create a PDF report.")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VyronSkillContextLoader.load(request)
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled setup must retain cancellation semantics.")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: library.installationDirectory.path))
        }
    }

    private func fixture() throws -> VyronAutomaticSkillTestLibrary {
        let library = try VyronAutomaticSkillTestLibrary()
        addTeardownBlock { try library.cleanUp() }
        return library
    }
}
