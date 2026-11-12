import Foundation
import XCTest
@testable import Vyron

final class VyronChatHandoffIntentTests: XCTestCase {
    private let projects = [
        "/Users/example/Projects/iOS-Study": "iOS Study",
        "/Users/example/Projects/Movie": "Movelle"
    ]

    func testExplicitDirectionPreservesRequestAndFindsSavedProject() throws {
        let prompt = "  Please move this request to the iOS-Study folder.  "
        let intent = try XCTUnwrap(VyronChatHandoffIntent(prompt: prompt, projects: projects))
        XCTAssertEqual(intent.request, prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(intent.projectPath, "/Users/example/Projects/iOS-Study")
    }

    func testCompoundArticleRequestResolvesWithoutDiscardingArticleInstructions() throws {
        let prompt = "Write an article about AI bits and memory. Move this request to iOS-Study and publish it."
        let intent = try XCTUnwrap(VyronChatHandoffIntent(prompt: prompt, projects: projects))
        XCTAssertEqual(intent.request, prompt)
        XCTAssertEqual(intent.projectPath, "/Users/example/Projects/iOS-Study")
        let originalStyle = "write an article at devopedia.dev  move this request to the iOS-study folder"
        XCTAssertNotNil(VyronChatHandoffIntent(prompt: originalStyle, projects: projects))
    }

    func testExplicitRequestFormsAndSavedNameAliases() {
        for prompt in [
            "SEND THIS TASK TO IOS STUDY",
            "Could you transfer this conversation and its context into Movelle?",
            "Hand this request off to Movelle.",
            "Continue this chat in iOS Study.",
            "Write the article and send this request to iOS-Study.",
            "I want you to handoff this task to Movelle.",
            "move this request to /Users/example/Projects/iOS-Study"
        ] {
            XCTAssertNotNil(VyronChatHandoffIntent(prompt: prompt, projects: projects), prompt)
        }
    }

    func testQuotedDestinationCanStillHintTheSavedProject() throws {
        for destination in ["\"iOS Study\"", "`iOS-Study`", "“iOS Study”"] {
            let intent = try XCTUnwrap(VyronChatHandoffIntent(
                prompt: "Send this request to \(destination) project.", projects: projects
            ))
            XCTAssertEqual(intent.projectPath, "/Users/example/Projects/iOS-Study")
        }
    }

    func testUnknownExplicitProjectOpensPickerWithoutInventingProjectPath() throws {
        for prompt in [
            "Move this request to another project.",
            "Send this task to the Experiments project.",
            "Continue this conversation in project Research.",
            "Move this request to /tmp/unregistered folder."
        ] {
            let intent = try XCTUnwrap(VyronChatHandoffIntent(prompt: prompt, projects: projects), prompt)
            XCTAssertNil(intent.projectPath, prompt)
        }
    }

    func testAmbiguousProjectNameDoesNotSelectOneArbitrarily() throws {
        let sameNames = ["/one/App": "App", "/two/App": "App"]
        let intent = try XCTUnwrap(VyronChatHandoffIntent(prompt: "Move this task to App.", projects: sameNames))
        XCTAssertNil(intent.projectPath)
    }

    func testDoesNotTreatSimilarLongerNameAsSavedProject() {
        XCTAssertNil(VyronChatHandoffIntent(prompt: "Move this request to iOS-Study-Archive.", projects: projects))
        XCTAssertNil(VyronChatHandoffIntent(prompt: "Move this request to iOS Study2.", projects: projects))
        XCTAssertNil(VyronChatHandoffIntent(prompt: "Move this request to iOS Study Archive.", projects: projects))
    }

    func testDiscussionsQuestionsAndOtherRecipientsDoNotNavigate() {
        for prompt in [
            "Implement a handoff feature.",
            "What is handoff?",
            "Can I move a chat to iOS-Study?",
            "How do I send this task to iOS-Study?",
            "Explain how to move this request to another project.",
            "The app should move this request to iOS-Study.",
            "Please do not move this request to iOS-Study.",
            "Send this request to my manager.",
            "Move this request to /tmp/unregistered.",
            "Send the report to Movelle.",
            "Continue this chat about project architecture.",
            "Implement a button labeled Move this request to another project."
        ] {
            XCTAssertNil(VyronChatHandoffIntent(prompt: prompt, projects: projects), prompt)
        }
    }

    func testQuotedInstructionsAndCodeAreReferenceText() {
        for prompt in [
            "\"Move this request to iOS-Study.\"",
            "The button says 'Send this request to another project'.",
            "“Continue this chat in Movelle.”",
            "`Move this request to iOS-Study`",
            "> Move this request to iOS-Study.",
            "```text\nMove this request to iOS-Study.\n```",
            "~~~\nSend this task to another project.\n~~~",
            "```\nMove this request to iOS-Study."
        ] {
            XCTAssertNil(VyronChatHandoffIntent(prompt: prompt, projects: projects), prompt)
        }
    }

    func testActualDirectionOutsideQuotedReferenceIsStillDetected() throws {
        let prompt = "The label is \"Move this request to Movelle\". Send this task to iOS-Study."
        let intent = try XCTUnwrap(VyronChatHandoffIntent(prompt: prompt, projects: projects))
        XCTAssertEqual(intent.projectPath, "/Users/example/Projects/iOS-Study")
    }

    func testClearTurkishAndUkrainianRequests() throws {
        for prompt in [
            "Lütfen bu isteği iOS-Study projesine taşı.",
            "Bu görevi Movelle projesine gönder.",
            "Перенеси цей запит до iOS-Study.",
            "Будь ласка, передай це завдання до Movelle."
        ] {
            XCTAssertNotNil(VyronChatHandoffIntent(prompt: prompt, projects: projects), prompt)
        }
    }

    func testBoundsRejectOversizedRequests() {
        XCTAssertNil(VyronChatHandoffIntent(prompt: " \n ", projects: projects))
        let oversized = "Move this request to iOS-Study. " + String(repeating: "a", count: 3_001)
        XCTAssertNil(VyronChatHandoffIntent(prompt: oversized, projects: projects))
        let oversizedUTF8 = "Move this request to iOS-Study. a" + String(repeating: "\u{301}", count: 6_000)
        XCTAssertLessThan(oversizedUTF8.count, 3_000)
        XCTAssertNil(VyronChatHandoffIntent(prompt: oversizedUTF8, projects: projects))
    }
}
