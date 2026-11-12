import AppKit
import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronComposerReturnKeyTests: XCTestCase {
    func testShiftReturnInsertsNewlineAtCursorWithoutSubmitting() {
        let editor = textView("first second", selection: NSRange(location: 5, length: 0))
        var submissionCount = 0

        let result = VyronComposerReturnKey.handle(modifiers: .shift, editor: editor) {
            submissionCount += 1
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(editor.string, "first\n second")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(submissionCount, 0)
    }

    func testShiftReturnReplacesSelectedText() {
        let editor = textView("first selected last", selection: NSRange(location: 6, length: 8))
        var submissionCount = 0

        let result = VyronComposerReturnKey.handle(modifiers: .shift, editor: editor) {
            submissionCount += 1
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(editor.string, "first \n last")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertEqual(submissionCount, 0)
    }

    func testShiftReturnPreservesUTF16SelectionAfterEmoji() {
        let draft = "🙂 café"
        let selection = (draft as NSString).range(of: "café")
        let editor = textView(draft, selection: selection)
        var submissionCount = 0

        let result = VyronComposerReturnKey.handle(modifiers: .shift, editor: editor) {
            submissionCount += 1
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(editor.string, "🙂 \n")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(submissionCount, 0)
    }

    func testRepeatedShiftReturnCreatesBlankLinesInEmptyDraft() {
        let editor = textView("", selection: NSRange(location: 0, length: 0))
        var submissionCount = 0

        for _ in 0..<3 {
            let result = VyronComposerReturnKey.handle(modifiers: .shift, editor: editor) {
                submissionCount += 1
            }
            XCTAssertEqual(result, .handled)
        }

        XCTAssertEqual(editor.string, "\n\n\n")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(submissionCount, 0)
    }

    func testShiftReturnWithCapsLockInsertsNewline() {
        let editor = textView("draft", selection: NSRange(location: 5, length: 0))
        var submissionCount = 0

        let result = VyronComposerReturnKey.handle(modifiers: [.shift, .capsLock], editor: editor) {
            submissionCount += 1
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(editor.string, "draft\n")
        XCTAssertEqual(submissionCount, 0)
    }

    func testShiftReturnDoesNotAcceptSlashCommand() {
        let editor = textView("/compact", selection: NSRange(location: 8, length: 0))
        var acceptedCommand = false

        let result = VyronComposerReturnKey.handle(modifiers: .shift, editor: editor) {
            acceptedCommand = true
        }

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(editor.string, "/compact\n")
        XCTAssertFalse(acceptedCommand)
    }

    func testPlainReturnAndCapsLockReturnSubmitWithoutEditing() {
        let editor = textView("draft", selection: NSRange(location: 2, length: 0))
        var submissionCount = 0
        let modifierCombinations: [EventModifiers] = [[], .capsLock]

        for modifiers in modifierCombinations {
            let result = VyronComposerReturnKey.handle(modifiers: modifiers, editor: editor) {
                submissionCount += 1
            }
            XCTAssertEqual(result, .handled)
        }

        XCTAssertEqual(editor.string, "draft")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(submissionCount, 2)
    }

    func testOtherModifiersRemainAvailableToExistingShortcuts() {
        let editor = textView("draft", selection: NSRange(location: 2, length: 0))
        var submissionCount = 0
        let modifierCombinations: [EventModifiers] = [
            .command, .option, .control,
            [.shift, .command], [.shift, .option], [.shift, .control],
            [.command, .capsLock]
        ]

        for modifiers in modifierCombinations {
            let result = VyronComposerReturnKey.handle(modifiers: modifiers, editor: editor) {
                submissionCount += 1
            }
            XCTAssertEqual(result, .ignored)
        }

        XCTAssertEqual(editor.string, "draft")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(submissionCount, 0)
    }

    func testMarkedTextKeepsReturnUnderInputMethodControl() {
        let editor = textView("prefix ", selection: NSRange(location: 7, length: 0))
        editor.setMarkedText(
            "に",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(editor.hasMarkedText())
        let originalText = editor.string
        let originalSelection = editor.selectedRange()
        let originalMarkedRange = editor.markedRange()
        var submissionCount = 0
        let modifierCombinations: [EventModifiers] = [[], .shift, .capsLock, [.shift, .capsLock]]

        for modifiers in modifierCombinations {
            let result = VyronComposerReturnKey.handle(modifiers: modifiers, editor: editor) {
                submissionCount += 1
            }
            XCTAssertEqual(result, .ignored)
        }

        XCTAssertEqual(editor.string, originalText)
        XCTAssertEqual(editor.selectedRange(), originalSelection)
        XCTAssertEqual(editor.markedRange(), originalMarkedRange)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(submissionCount, 0)
    }

    func testMissingEditorLeavesShiftReturnUnconsumedAndPlainReturnStillSubmits() {
        var submissionCount = 0

        let shiftResult = VyronComposerReturnKey.handle(modifiers: .shift, editor: nil) {
            submissionCount += 1
        }
        XCTAssertEqual(shiftResult, .ignored)
        XCTAssertEqual(submissionCount, 0)

        let plainResult = VyronComposerReturnKey.handle(modifiers: [], editor: nil) {
            submissionCount += 1
        }
        XCTAssertEqual(plainResult, .handled)
        XCTAssertEqual(submissionCount, 1)
    }

    private func textView(_ text: String, selection: NSRange) -> NSTextView {
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false
        editor.string = text
        editor.setSelectedRange(selection)
        return editor
    }
}
