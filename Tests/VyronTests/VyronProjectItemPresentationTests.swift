import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronProjectItemPresentationTests: XCTestCase {
    func testItemReviewPreservesBothPathsAndUsesAnActionSpecificConfirmation() {
        let operation = "/Projects/100% %@/Eski dosya.swift\n→ /Projects/Новий каталог/New file.swift"
        let actions: [VyronDevelopmentApprovalAction] = [.moveProjectItem, .renameProjectItem, .trashProjectItem]
        var titles: Set<String> = []
        var buttons: Set<String> = []
        for action in actions {
            let approval = CommandApproval(command: operation, reason: "Internal review reason", action: action)
            let details = VyronProjectApprovalPresentation.reviewDetails(approval, workspacePath: "/Unrelated project")

            XCTAssertTrue(details.contains(operation))
            XCTAssertFalse(details.contains("Internal review reason"))
            XCTAssertFalse(details.contains("/Unrelated project"))
            let title = VyronProjectApprovalPresentation.reviewTitle(action)
            let button = VyronProjectApprovalPresentation.confirmationTitle(action)
            XCTAssertNotEqual(title, VyronGeneralText.reviewCommand)
            XCTAssertNotEqual(button, VyronGeneralText.runCommand)
            titles.insert(title)
            buttons.insert(button)
        }
        XCTAssertEqual(titles.count, actions.count)
        XCTAssertEqual(buttons.count, actions.count)
    }

    func testCommandAndFolderReviewsPreserveTheirExistingPresentation() {
        let command = CommandApproval(command: "swift test", reason: "Existing reason")
        XCTAssertEqual(VyronProjectApprovalPresentation.reviewTitle(.command), VyronGeneralText.reviewCommand)
        XCTAssertEqual(VyronProjectApprovalPresentation.confirmationTitle(.command), VyronGeneralText.runCommand)
        XCTAssertEqual(
            VyronProjectApprovalPresentation.reviewDetails(command, workspacePath: "/Project"),
            VyronGeneralText.commandReviewDetails("swift test", "Existing reason", "/Project")
        )
        let folder = CommandApproval(command: "/Desktop/New project", reason: "Folder review", action: .createFolder)
        XCTAssertEqual(VyronProjectApprovalPresentation.reviewTitle(.createFolder), VyronFolderText.reviewTitle)
        XCTAssertEqual(VyronProjectApprovalPresentation.confirmationTitle(.createFolder), VyronFolderText.allow)
        XCTAssertEqual(
            VyronProjectApprovalPresentation.reviewDetails(folder, workspacePath: "/Project"),
            VyronFolderText.reviewDetails("/Desktop/New project")
        )
    }

    func testCommandReviewSelectsPolicyCopyBySource() throws {
        let fallback = try XCTUnwrap(VyronProjectApprovalMode.askForApproval.commandReviewReason(for: nil))
        let policy = CommandApproval(command: "swift test", reason: fallback, reviewSource: .approvalSetting)
        let classified = CommandApproval(command: "swift test", reason: fallback)
        XCTAssertEqual(
            VyronProjectApprovalPresentation.reviewDetails(policy, workspacePath: "/Project"),
            VyronGeneralText.commandReviewDetails("swift test", VyronWorkspaceText.approvalReviewReason, "/Project")
        )
        XCTAssertEqual(
            VyronProjectApprovalPresentation.reviewDetails(classified, workspacePath: "/Project"),
            VyronGeneralText.commandReviewDetails("swift test", fallback, "/Project")
        )
    }

    func testConversationMoveReviewShowsTheChatAndExactDestination() {
        let destination = "/Projects/Study 100% %@"
        let title = "Existing conversation"
        let review = CommandApproval(command: destination, reason: "Folder review", action: .moveConversation)
        let details = VyronProjectApprovalPresentation.reviewDetails(
            review, workspacePath: "/Original", conversationTitle: title
        )

        XCTAssertEqual(VyronProjectApprovalPresentation.reviewTitle(.moveConversation), VyronSidebarText.moveTo)
        XCTAssertEqual(
            VyronProjectApprovalPresentation.confirmationTitle(.moveConversation), VyronProjectItemText.moveAllow
        )
        XCTAssertTrue(details.contains(title))
        XCTAssertTrue(details.contains(destination))
        XCTAssertFalse(details.contains("/Original"))
    }

    func testOperationTitlesAndButtonsHaveTranslationsForAllSupportedLanguages() {
        let keys = [
            "projectItemMoveReviewTitle", "projectItemMoveAllow",
            "projectItemRenameReviewTitle", "projectItemRenameAllow",
            "projectItemTrashReviewTitle", "projectItemTrashAllow"
        ]
        let examples: [(VyronLanguage, [String])] = [
            (.english, [
                "Move this item?", "Move", "Rename this item?", "Rename", "Move this item to Trash?", "Move to Trash"
            ]),
            (.turkish, [
                "Bu öğe taşınsın mı?", "Taşı", "Bu öğe yeniden adlandırılsın mı?", "Yeniden adlandır",
                "Bu öğe Çöp Sepeti’ne taşınsın mı?", "Çöp Sepeti’ne taşı"
            ]),
            (.ukrainian, [
                "Перемістити цей об’єкт?", "Перемістити", "Перейменувати цей об’єкт?", "Перейменувати",
                "Перемістити цей об’єкт у Смітник?", "Перемістити в Смітник"
            ])
        ]
        for (language, expected) in examples {
            for (key, value) in zip(keys, expected) {
                XCTAssertEqual(VyronResourceBundle.string(key, fallback: "Missing review", language: language), value)
            }
        }
    }

    func testTranslatedDetailsKeepDynamicFilenamesAndLineBreaks() {
        let operation = "Sources/100% %@/Старе ім’я.swift\n→ Sources/Yeni dosya.swift"
        let keys = ["projectItemMoveReviewDetails", "projectItemRenameReviewDetails", "projectItemTrashReviewDetails"]
        for language in [VyronLanguage.english, .turkish, .ukrainian] {
            for key in keys {
                let text = VyronResourceBundle.format(
                    key, fallback: "Missing review", arguments: [operation], language: language
                )
                XCTAssertTrue(text.contains(operation))
                XCTAssertEqual(text.components(separatedBy: operation).count, 2)
                XCTAssertFalse(text.contains("Missing review"))
            }
        }
    }

    func testNativeFileOperationsUseLocalizedEditActivitiesAndKeepFailureText() {
        let examples = [
            ("move_item", VyronProjectItemText.moving, VyronProjectItemText.moved),
            ("rename_item", VyronProjectItemText.renaming, VyronProjectItemText.renamed),
            ("trash_item", VyronProjectItemText.trashing, VyronProjectItemText.trashed)
        ]
        for (tool, started, finished) in examples {
            let start = DevelopmentEvent(kind: .toolStarted, message: "Applying file operation", tool: tool)
            let success = DevelopmentEvent(kind: .toolFinished, message: "File operation completed", tool: tool)
            let changed = DevelopmentEvent(kind: .fileChanged, message: "File operation completed", tool: tool)
            let failure = DevelopmentEvent(
                kind: .toolFinished, message: "Tool could not complete", tool: tool,
                failure: "The item changed before the operation."
            )
            XCTAssertEqual(start.localizedMessage, started)
            XCTAssertEqual(success.localizedMessage, finished)
            XCTAssertEqual(changed.localizedMessage, finished)
            XCTAssertEqual(failure.localizedMessage, "Tool could not complete")
            XCTAssertEqual(start.activityCategory, .edit)
            XCTAssertEqual(success.activityCategory, .edit)
            XCTAssertEqual(changed.activityCategory, .edit)
            XCTAssertEqual(failure.activityCategory, .edit)
        }
    }
}
