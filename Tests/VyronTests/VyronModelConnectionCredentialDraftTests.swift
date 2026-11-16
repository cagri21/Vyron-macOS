import XCTest
@testable import Vyron

final class VyronModelConnectionCredentialDraftTests: XCTestCase {
    func testServerChangeRequiresReplacementForAPreviouslySavedKey() {
        var draft = VyronModelConnectionCredentialDraft()
        draft.loadSavedKey("fixture-saved-key")
        XCTAssertTrue(draft.canSave)

        draft.clearForServerChange()
        XCTAssertEqual(draft.key, "")
        XCTAssertFalse(draft.canSave)

        draft.key = "  "
        XCTAssertFalse(draft.canSave)
        draft.key = "fixture-replacement-key"
        XCTAssertTrue(draft.canSave)

        draft.clearForServerChange()
        XCTAssertEqual(draft.key, "")
        XCTAssertFalse(draft.canSave)
    }

    func testSwitchingAwayFromAnUnsavedKeyKeepsSaveAvailable() {
        var draft = VyronModelConnectionCredentialDraft()
        draft.key = "fixture-unsaved-key"

        draft.clearForServerChange()
        XCTAssertEqual(draft.key, "")
        XCTAssertTrue(draft.canSave)
    }
}
