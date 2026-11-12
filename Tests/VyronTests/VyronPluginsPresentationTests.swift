import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronPluginsPresentationTests: XCTestCase {
    func testInstalledAndConnectedFiltersKeepSavedProfilesSorted() {
        let presentation = VyronPluginsPresentation()
        let zebra = MCPConnectionProfile(name: "Zebra", endpoint: "https://zebra.example/mcp")
        let alpha = MCPConnectionProfile(name: "Alpha", endpoint: "https://alpha.example/mcp", enabled: false)
        let penpot = MCPConnectionProfile(name: "Penpot", endpoint: "https://design.example/mcp")
        let profiles = [zebra, penpot, alpha]
        let connectedIDs: Set<UUID> = [penpot.id, UUID()]

        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: connectedIDs), [alpha, penpot, zebra])

        presentation.filter = .installed
        XCTAssertEqual(
            presentation.visibleProfiles(profiles, connectedIDs: connectedIDs),
            [alpha, penpot, zebra],
            "Installed includes disabled saved profiles as well as connected profiles."
        )

        presentation.filter = .connected
        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: connectedIDs), [penpot])
        XCTAssertTrue(presentation.visibleProfiles(profiles, connectedIDs: []).isEmpty)
        XCTAssertEqual(profiles.map(\.id), [zebra.id, penpot.id, alpha.id], "Filtering must preserve source order.")
    }

    func testSearchMatchesNamesHTTPAddressesAndLocalExecutablesWithoutChangingProfiles() {
        let presentation = VyronPluginsPresentation()
        let penpot = MCPConnectionProfile(name: "Penpot", endpoint: "https://design.example/mcp")
        let local = MCPConnectionProfile(
            name: "Local documentation",
            transport: .stdio,
            command: "/opt/tools/documentation-server"
        )
        let profiles = [penpot, local]

        presentation.searchQuery = "  PENPOT\n"
        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: []), [penpot])

        presentation.searchQuery = "DESIGN.EXAMPLE"
        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: []), [penpot])

        presentation.searchQuery = "documentation-server"
        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: []), [local])

        presentation.searchQuery = "not-a-configured-tool"
        XCTAssertTrue(presentation.visibleProfiles(profiles, connectedIDs: []).isEmpty)

        presentation.searchQuery = " \n\t "
        XCTAssertEqual(presentation.visibleProfiles(profiles, connectedIDs: []), [local, penpot])
        XCTAssertEqual(profiles, [penpot, local])
    }

    func testConnectedFilterAndSearchAreCombinedAndCatalogSearchUsesDetails() {
        let presentation = VyronPluginsPresentation()
        let local = MCPConnectionProfile(name: "Local design", endpoint: "http://localhost:4401/mcp")
        let remote = MCPConnectionProfile(name: "Remote design", endpoint: "https://design.example/mcp")
        presentation.filter = .connected
        presentation.searchQuery = "design"

        XCTAssertEqual(presentation.visibleProfiles([local, remote], connectedIDs: [remote.id]), [remote])

        presentation.searchQuery = "localhost"
        XCTAssertTrue(presentation.visibleProfiles([local, remote], connectedIDs: [remote.id]).isEmpty)

        presentation.searchQuery = "layout"
        XCTAssertTrue(presentation.matchesSearch("Penpot", detail: "Inspect design layout and tokens"))
        XCTAssertFalse(presentation.matchesSearch("Custom MCP", detail: "Connect a service"))
    }

    func testSelectionSurvivesEditsAndOtherRemovalsThenClearsWhenSelectedConnectionIsRemoved() {
        let presentation = VyronPluginsPresentation()
        let selected = MCPConnectionProfile(name: "Penpot", endpoint: "https://design.example/mcp")
        let other = MCPConnectionProfile(name: "Other", endpoint: "https://other.example/mcp")
        presentation.select(selected.id)
        presentation.searchQuery = "existing search"
        presentation.filter = .installed

        presentation.reconcileSelection(with: [selected])
        XCTAssertEqual(presentation.selectedConnectionID, selected.id)

        var renamed = selected
        renamed.name = "Renamed design service"
        presentation.reconcileSelection(with: [renamed, other])
        XCTAssertEqual(
            presentation.selectedConnectionID,
            selected.id,
            "Selection uses identity rather than a profile copy."
        )

        presentation.reconcileSelection(with: [other])
        XCTAssertNil(presentation.selectedConnectionID)
        XCTAssertEqual(presentation.searchQuery, "existing search")
        XCTAssertEqual(presentation.filter, .installed)

        presentation.reconcileSelection(with: [])
        XCTAssertNil(presentation.selectedConnectionID)
    }

    func testReturningToSearchKeepsFilterAndQueryWhileShowAllResetsBoth() {
        let presentation = VyronPluginsPresentation()
        presentation.filter = .connected
        presentation.searchQuery = "Penpot"
        presentation.select(UUID())

        presentation.showSearchResults()
        XCTAssertNil(presentation.selectedConnectionID)
        XCTAssertEqual(presentation.filter, .connected)
        XCTAssertEqual(presentation.searchQuery, "Penpot")

        presentation.select(UUID())
        presentation.showAll()
        XCTAssertNil(presentation.selectedConnectionID)
        XCTAssertEqual(presentation.filter, .all)
        XCTAssertEqual(presentation.searchQuery, "")
    }

    func testAddPenpotAndCustomConnectionsOpenIndependentUnsavedEditorProfiles() throws {
        let presentation = VyronPluginsPresentation()
        let selectedID = UUID()
        presentation.select(selectedID)
        presentation.searchQuery = "existing search"
        presentation.filter = .installed

        presentation.addPenpot()
        let penpot = try XCTUnwrap(presentation.editingProfile)
        XCTAssertEqual(penpot.name, "Penpot")
        XCTAssertEqual(penpot.transport, .http)
        XCTAssertEqual(penpot.endpoint, "http://localhost:4401/mcp")
        XCTAssertEqual(penpot.permission, .askForWrites)
        XCTAssertTrue(penpot.enabled)

        presentation.addPenpot()
        XCTAssertNotEqual(
            presentation.editingProfile?.id,
            penpot.id,
            "A new preset must not overwrite an earlier profile."
        )

        presentation.addConnection()
        let custom = try XCTUnwrap(presentation.editingProfile)
        XCTAssertEqual(custom.name, "")
        XCTAssertEqual(custom.transport, .http)
        XCTAssertEqual(custom.endpoint, "")
        XCTAssertEqual(custom.command, "")
        XCTAssertTrue(custom.arguments.isEmpty)
        XCTAssertEqual(custom.permission, .readOnly)
        XCTAssertTrue(custom.enabled)
        XCTAssertNotEqual(custom.id, penpot.id)
        XCTAssertEqual(presentation.selectedConnectionID, selectedID)
        XCTAssertEqual(presentation.searchQuery, "existing search")
        XCTAssertEqual(presentation.filter, .installed)
        XCTAssertNil(presentation.removingProfile)
    }

    func testHTTPJSONEditorRetainsLegacyKeysAndFormIdentity() throws {
        let original = MCPConnectionProfile(
            name: "Remote design",
            endpoint: "https://design.example/mcp",
            enabled: false,
            permission: .askForWrites
        )
        let encoded = try JSONEncoder().encode(VyronMCPConnectionJSON(original))
        let keys = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: encoded)

        XCTAssertEqual(Set(keys.keys), ["name", "type", "url", "enabled", "permission"])
        XCTAssertEqual(keys["type"], .string("http"))
        XCTAssertEqual(keys["url"], .string(original.endpoint))
        XCTAssertEqual(keys["permission"], .string("askForWrites"))
        XCTAssertNil(keys["id"], "Identity belongs to the saved connection and is supplied when applying JSON edits.")

        let decoded = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: encoded)
        XCTAssertEqual(decoded.profile(id: original.id), original)
    }

    func testStdioJSONEditorRetainsLegacyKeysArgumentsAndPermission() throws {
        let original = MCPConnectionProfile(
            name: "Local tools",
            transport: .stdio,
            command: "/usr/local/bin/design-server",
            arguments: ["--project", "Folder with spaces", "literal $(text)"],
            permission: .askForWrites
        )
        let encoded = try JSONEncoder().encode(VyronMCPConnectionJSON(original))
        let keys = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: encoded)

        XCTAssertEqual(Set(keys.keys), ["name", "type", "command", "args", "enabled", "permission"])
        XCTAssertEqual(keys["type"], .string("stdio"))
        XCTAssertEqual(keys["args"], .array(original.arguments.map(DevelopmentJSONValue.string)))
        XCTAssertNil(keys["url"])

        let decoded = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: encoded)
        XCTAssertEqual(decoded.profile(id: original.id), original)
    }

    func testJSONEditsApplyToSameConnectionAndMinimalLegacyJSONKeepsSafeDefaults() throws {
        let original = MCPConnectionProfile(name: "Original", endpoint: "https://old.example/mcp")
        var editor = VyronMCPConnectionJSON(original)
        editor.name = "Renamed"
        editor.url = "https://new.example/mcp"
        editor.permission = .askForWrites
        editor.enabled = false
        let editedData = try JSONEncoder().encode(editor)
        let form = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: editedData).profile(id: original.id)

        XCTAssertEqual(form.id, original.id)
        XCTAssertEqual(form.name, "Renamed")
        XCTAssertEqual(form.endpoint, "https://new.example/mcp")
        XCTAssertEqual(form.permission, .askForWrites)
        XCTAssertFalse(form.enabled)
        let formData = try JSONEncoder().encode(VyronMCPConnectionJSON(form))
        let roundTrip = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: formData).profile(id: original.id)
        XCTAssertEqual(roundTrip, form)

        let minimal = Data(#"{"name":"Legacy local","type":"stdio","command":"/usr/bin/server"}"#.utf8)
        let legacy = try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: minimal).profile(id: original.id)
        XCTAssertEqual(legacy.id, original.id)
        XCTAssertEqual(legacy.permission, .readOnly)
        XCTAssertTrue(legacy.enabled)
        XCTAssertTrue(legacy.arguments.isEmpty)
        XCTAssertEqual(legacy.endpoint, "")
        XCTAssertEqual(legacy.command, "/usr/bin/server")
    }
}
