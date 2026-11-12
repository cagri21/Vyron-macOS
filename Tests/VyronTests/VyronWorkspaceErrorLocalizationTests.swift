import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronWorkspaceErrorLocalizationTests: XCTestCase {
    func testOpeningValidWorkspaceClearsPreviousWorkspaceFailure() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let missing = test.directory.appendingPathComponent("Missing", isDirectory: true)

        await test.model.loadWorkspace(missing)
        XCTAssertNotNil(test.model.errorMessage)

        await test.model.loadWorkspace(test.directory)

        XCTAssertNil(test.model.errorMessage)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, test.directory.standardizedFileURL)
    }

    func testOpeningValidWorkspacePreservesNewerUnrelatedError() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let missing = test.directory.appendingPathComponent("Missing", isDirectory: true)

        await test.model.loadWorkspace(missing)
        XCTAssertNotNil(test.model.errorMessage)
        let newerError = "An unrelated error that should remain visible."
        test.model.errorMessage = newerError

        await test.model.loadWorkspace(test.directory)

        XCTAssertEqual(test.model.errorMessage, newerError)
    }
}
