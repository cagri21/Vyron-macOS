import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronCodexCatalogPresetTests: XCTestCase {
    func testBundledPresetUsesReadOnlyIsolatedPythonAndAbsoluteResourcePath() throws {
        let script = try XCTUnwrap(VyronCodexCatalogPreset.bundledScriptURL)
        let profile = try XCTUnwrap(VyronCodexCatalogPreset.makeProfile())
        XCTAssertEqual(profile.transport, .stdio)
        XCTAssertEqual(profile.command, "python3")
        XCTAssertEqual(profile.arguments, ["-I", script.path])
        XCTAssertEqual(profile.permission, .readOnly)
        XCTAssertTrue(profile.enabled)
        XCTAssertTrue(profile.endpoint.isEmpty)
        XCTAssertTrue(script.path.hasPrefix("/"))
        XCTAssertEqual(try profile.validated(), profile)
    }

    func testMissingNonFileAndDirectoryResourcesCannotProduceAProfile() {
        XCTAssertNil(VyronCodexCatalogPreset.makeProfile(scriptURL: nil))
        XCTAssertNil(VyronCodexCatalogPreset.makeProfile(scriptURL: URL(string: "https://example.com/helper.py")))
        XCTAssertNil(VyronCodexCatalogPreset.makeProfile(scriptURL: FileManager.default.temporaryDirectory))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-\(UUID()).py")
        XCTAssertNil(VyronCodexCatalogPreset.makeProfile(scriptURL: missing))
    }

    func testOpeningCatalogOnlyPreparesAnIndependentUnsavedEditorAndPreservesNavigation() throws {
        let presentation = VyronPluginsPresentation()
        let selectedID = UUID()
        presentation.select(selectedID)
        presentation.searchQuery = "existing search"
        presentation.filter = .installed
        presentation.addCodexCatalog()
        let first = try XCTUnwrap(presentation.editingProfile)
        XCTAssertEqual(first.permission, .readOnly)
        XCTAssertEqual(first.transport, .stdio)
        XCTAssertEqual(presentation.selectedConnectionID, selectedID)
        XCTAssertEqual(presentation.searchQuery, "existing search")
        XCTAssertEqual(presentation.filter, .installed)
        XCTAssertNil(presentation.removingProfile)
        presentation.addCodexCatalog()
        XCTAssertNotEqual(presentation.editingProfile?.id, first.id)
        XCTAssertNil(presentation.catalogError)
    }

    func testUnavailableResourceSurfacesErrorAndCanRecoverWithoutOverwritingAnEditor() throws {
        let presentation = VyronPluginsPresentation()
        presentation.addPenpot()
        let priorID = presentation.editingProfile?.id
        presentation.addCodexCatalog(scriptURL: nil)
        XCTAssertNotNil(presentation.catalogError)
        XCTAssertEqual(presentation.editingProfile?.id, priorID)
        presentation.addCodexCatalog()
        XCTAssertNil(presentation.catalogError)
        XCTAssertNotEqual(try XCTUnwrap(presentation.editingProfile).id, priorID)
    }

    func testPreparedCatalogJSONRoundTripsThroughExistingEditorFormat() throws {
        let profile = try XCTUnwrap(VyronCodexCatalogPreset.makeProfile())
        let data = try JSONEncoder().encode(VyronMCPConnectionJSON(profile))
        let decoded = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: data)
        XCTAssertEqual(decoded.profile(id: profile.id), profile)
        XCTAssertNil(decoded.url)
    }
}
