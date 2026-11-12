// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronHeaderText {
    static var openProjectXcode: String {
        VyronResourceBundle.string("headerOpenProjectXcode", fallback: "Xcode")
    }
    static var outputs: String {
        VyronResourceBundle.string("headerOutputs", fallback: "Outputs")
    }
    static var overview: String {
        VyronResourceBundle.string("headerOverview", fallback: "Task overview")
    }
    static var pin: String {
        VyronResourceBundle.string("headerPin", fallback: "Pin")
    }
    static var readOnlyWindow: String {
        VyronResourceBundle.string("headerReadOnlyWindow", fallback: "This window follows the conversation. Continue it in the main window.")
    }
    static var rename: String {
        VyronResourceBundle.string("headerRename", fallback: "Rename")
    }
    static var renameTitle: String {
        VyronResourceBundle.string("headerRenameTitle", fallback: "Rename chat")
    }
    static var save: String {
        VyronResourceBundle.string("headerSave", fallback: "Save")
    }
    static var scheduleTask: String {
        VyronResourceBundle.string("headerScheduleTask", fallback: "Add scheduled task…")
    }
    static var section: String {
        VyronResourceBundle.string("headerSection", fallback: "Section")
    }
    static var share: String {
        VyronResourceBundle.string("headerShare", fallback: "Share")
    }
    static var showInspector: String {
        VyronResourceBundle.string("headerShowInspector", fallback: "Show inspector")
    }
    static func sideChatContext(_ p1: String) -> String {
        VyronResourceBundle.format(
            "headerSideChatContext",
            fallback: "Read-only context from %@. This chat runs separately from the original task.",
            arguments: [p1]
        )
    }
    static var sideChatNoAnswer: String {
        VyronResourceBundle.string("headerSideChatNoAnswer", fallback: "The model returned an empty answer. Try again.")
    }
    static var sideChatRunning: String {
        VyronResourceBundle.string("headerSideChatRunning", fallback: "Stop this side chat before deleting it.")
    }
    static var sideChatSaveFailed: String {
        VyronResourceBundle.string("headerSideChatSaveFailed", fallback: "Could not save this side chat. Your draft was preserved.")
    }
    static var sideChatStopped: String {
        VyronResourceBundle.string("headerSideChatStopped", fallback: "Side chat stopped")
    }
    static func sideChatTitle(_ p1: String) -> String {
        VyronResourceBundle.format(
            "headerSideChatTitle",
            fallback: "Side chat · %@",
            arguments: [p1]
        )
    }
    static var sideChatUnavailable: String {
        VyronResourceBundle.string("headerSideChatUnavailable", fallback: "Connect a model before starting a side chat.")
    }
    static var sources: String {
        VyronResourceBundle.string("headerSources", fallback: "Sources")
    }
    static var subagents: String {
        VyronResourceBundle.string("headerSubagents", fallback: "Subagents")
    }
    static var unpin: String {
        VyronResourceBundle.string("headerUnpin", fallback: "Unpin")
    }
    static var unread: String {
        VyronResourceBundle.string("headerUnread", fallback: "Unread")
    }
    static var viewAll: String {
        VyronResourceBundle.string("headerViewAll", fallback: "View all")
    }
    static func workingCount(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "headerWorkingCount",
            fallback: "%d working",
            arguments: [p1]
        )
    }
}
