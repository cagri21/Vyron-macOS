import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronAgentCatalogPresetTests: XCTestCase {
    func testBundledBridgeStartsDisabledAndUsesIsolatedPythonWithExplicitHome() throws {
        let script = try XCTUnwrap(VyronAgentCatalogPreset.bundledScriptURL)
        let home = URL(fileURLWithPath: "/Fixture Home")
        let profile = try XCTUnwrap(VyronAgentCatalogPreset.makeProfile(scriptURL: script, homeDirectory: home))
        XCTAssertEqual(profile.transport, .stdio)
        XCTAssertEqual(profile.command, "python3")
        XCTAssertEqual(profile.arguments, ["-I", script.path, "--home-root", home.path])
        XCTAssertEqual(profile.permission, .readOnly)
        XCTAssertFalse(profile.enabled)
        XCTAssertEqual(try profile.validated(), profile)
    }

    func testProjectSelectionIsCapturedAsAnArgumentWithoutChangingTheHome() throws {
        let script = try XCTUnwrap(VyronAgentCatalogPreset.bundledScriptURL)
        let home = URL(fileURLWithPath: "/Fixture Home")
        let project = URL(fileURLWithPath: "/Projects/Project with spaces")
        let profile = try XCTUnwrap(VyronAgentCatalogPreset.makeProfile(
            scriptURL: script,
            homeDirectory: home,
            projectDirectory: project
        ))
        XCTAssertEqual(
            profile.arguments,
            ["-I", script.path, "--home-root", home.path, "--project-root", project.path]
        )
        let encoded = try JSONEncoder().encode(VyronMCPConnectionJSON(profile))
        let decoded = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: encoded)
        XCTAssertEqual(decoded.profile(id: profile.id), profile)
    }

    func testMissingOrNonFileResourcesAndRemoteRootsCannotProduceAProfile() throws {
        let script = try XCTUnwrap(VyronAgentCatalogPreset.bundledScriptURL)
        let remote = try XCTUnwrap(URL(string: "https://bridge.invalid/path"))
        XCTAssertNil(VyronAgentCatalogPreset.makeProfile(scriptURL: nil))
        XCTAssertNil(VyronAgentCatalogPreset.makeProfile(scriptURL: remote))
        XCTAssertNil(VyronAgentCatalogPreset.makeProfile(scriptURL: FileManager.default.temporaryDirectory))
        XCTAssertNil(VyronAgentCatalogPreset.makeProfile(scriptURL: script, homeDirectory: remote))
        XCTAssertNil(VyronAgentCatalogPreset.makeProfile(scriptURL: script, projectDirectory: remote))
    }

    func testOpeningBridgeOnlyPreparesEditorAndRecoversFromMissingResource() throws {
        let presentation = VyronPluginsPresentation()
        let selection = UUID()
        presentation.select(selection)
        presentation.searchQuery = "Keep this search"
        presentation.addPenpot()
        let originalEditorID = presentation.editingProfile?.id
        presentation.addAgentCatalog(scriptURL: nil)
        XCTAssertNotNil(presentation.catalogError)
        XCTAssertEqual(presentation.editingProfile?.id, originalEditorID)

        presentation.addAgentCatalog(projectDirectory: URL(fileURLWithPath: "/Project"))
        let profile = try XCTUnwrap(presentation.editingProfile)
        XCTAssertNotEqual(profile.id, originalEditorID)
        XCTAssertFalse(profile.enabled)
        XCTAssertEqual(profile.permission, .readOnly)
        XCTAssertEqual(profile.arguments.suffix(2), ["--project-root", "/Project"])
        XCTAssertEqual(presentation.selectedConnectionID, selection)
        XCTAssertEqual(presentation.searchQuery, "Keep this search")
        XCTAssertNil(presentation.catalogError)
    }
}
