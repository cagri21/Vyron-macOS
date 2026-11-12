// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronGeneralText {
    static var acceptSuggestedQuestion: String {
        VyronResourceBundle.string("generalAcceptSuggestedQuestion", fallback: "Use suggested follow-up")
    }
    static var addSuggestedQuestion: String {
        VyronResourceBundle.string("generalAddSuggestedQuestion", fallback: "Add this question to your draft")
    }
    static var chooseWorkspace: String {
        VyronResourceBundle.string("generalChooseWorkspace", fallback: "Choose Workspace…")
    }
    static var clearDraftForQuestion: String {
        VyronResourceBundle.string("generalClearDraftForQuestion", fallback: "Clear your draft to choose a suggested question")
    }
    static var code: String {
        VyronResourceBundle.string("generalCode", fallback: "code")
    }
    static func commandReviewDetails(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "generalCommandReviewDetails",
            fallback: "%@\n\n%@\n\nProject: %@",
            arguments: [p1, p2, p3]
        )
    }
    static var continueConversation: String {
        VyronResourceBundle.string("generalContinueConversation", fallback: "CONTINUE THE CONVERSATION")
    }
    static var copied: String {
        VyronResourceBundle.string("generalCopied", fallback: "Copied")
    }
    static var copy: String {
        VyronResourceBundle.string("generalCopy", fallback: "Copy")
    }
    static var copyResponse: String {
        VyronResourceBundle.string("generalCopyResponse", fallback: "Copy response")
    }
    static var invalidChatName: String {
        VyronResourceBundle.string("generalInvalidChatName", fallback: "Use a chat name between 1 and 120 characters without line breaks.")
    }
    static var loadingContext: String {
        VyronResourceBundle.string("generalLoadingContext", fallback: "Loading context and preparing a response…")
    }
    static var newTask: String {
        VyronResourceBundle.string("generalNewTask", fallback: "New Task")
    }
    static var noProject: String {
        VyronResourceBundle.string("generalNoProject", fallback: "No project")
    }
    static var reviewCommand: String {
        VyronResourceBundle.string("generalReviewCommand", fallback: "Review local command")
    }
    static var runCommand: String {
        VyronResourceBundle.string("generalRunCommand", fallback: "Run command")
    }
    static var suggestedQuestionHint: String {
        VyronResourceBundle.string("generalSuggestedQuestionHint", fallback: "Adds this question to the composer for you to review before sending")
    }
    static var suggestedQuestionTabHint: String {
        VyronResourceBundle.string("generalSuggestedQuestionTabHint", fallback: "Press Tab to add this suggestion to your draft")
    }
    static var you: String {
        VyronResourceBundle.string("generalYou", fallback: "YOU")
    }
}
