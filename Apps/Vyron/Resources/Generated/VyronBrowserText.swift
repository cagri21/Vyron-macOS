// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronBrowserText {
    static var addressPlaceholder: String {
        VyronResourceBundle.string("browserAddressPlaceholder", fallback: "Search or enter a URL")
    }
    static var back: String {
        VyronResourceBundle.string("browserBack", fallback: "Back")
    }
    static var blankPage: String {
        VyronResourceBundle.string("browserBlankPage", fallback: "Untitled page")
    }
    static var blockedNavigation: String {
        VyronResourceBundle.string("browserBlockedNavigation", fallback: "This link cannot open in Vyron. Only http and https websites are supported.")
    }
    static var cancel: String {
        VyronResourceBundle.string("browserCancel", fallback: "Cancel")
    }
    static var closeTab: String {
        VyronResourceBundle.string("browserCloseTab", fallback: "Close tab")
    }
    static var closeUnsavedTitle: String {
        VyronResourceBundle.string("browserCloseUnsavedTitle", fallback: "Save changes before closing this tab?")
    }
    static var conversation: String {
        VyronResourceBundle.string("browserConversation", fallback: "Conversation")
    }
    static var discard: String {
        VyronResourceBundle.string("browserDiscard", fallback: "Discard")
    }
    static var forward: String {
        VyronResourceBundle.string("browserForward", fallback: "Forward")
    }
    static var home: String {
        VyronResourceBundle.string("browserHome", fallback: "Home")
    }
    static var insecureConnection: String {
        VyronResourceBundle.string("browserInsecureConnection", fallback: "Connection uses HTTP")
    }
    static var invalidAddress: String {
        VyronResourceBundle.string("browserInvalidAddress", fallback: "Enter a website address or search query. Only http and https websites are supported.")
    }
    static var loadFailed: String {
        VyronResourceBundle.string("browserLoadFailed", fallback: "This page could not be loaded.")
    }
    static var loading: String {
        VyronResourceBundle.string("browserLoading", fallback: "Loading…")
    }
    static func navigationFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "browserNavigationFailed",
            fallback: "Could not load this website: %@",
            arguments: [p1]
        )
    }
    static var newTab: String {
        VyronResourceBundle.string("browserNewTab", fallback: "New tab")
    }
    static var openExternal: String {
        VyronResourceBundle.string("browserOpenExternal", fallback: "Open in default browser")
    }
    static var openPage: String {
        VyronResourceBundle.string("browserOpenPage", fallback: "Open page")
    }
    static var pageDeleted: String {
        VyronResourceBundle.string("browserPageDeleted", fallback: "This page was deleted.")
    }
    static var processStopped: String {
        VyronResourceBundle.string("browserProcessStopped", fallback: "The website stopped responding. Reload to try again.")
    }
    static var processTerminated: String {
        VyronResourceBundle.string("browserProcessTerminated", fallback: "The website stopped responding. Reload to try again.")
    }
    static var reload: String {
        VyronResourceBundle.string("browserReload", fallback: "Reload")
    }
    static var retry: String {
        VyronResourceBundle.string("browserRetry", fallback: "Retry")
    }
    static var save: String {
        VyronResourceBundle.string("browserSave", fallback: "Save")
    }
    static var savePage: String {
        VyronResourceBundle.string("browserSavePage", fallback: "Save page")
    }
    static var secureConnection: String {
        VyronResourceBundle.string("browserSecureConnection", fallback: "Secure connection")
    }
    static var stop: String {
        VyronResourceBundle.string("browserStop", fallback: "Stop loading")
    }
    static var tabLimit: String {
        VyronResourceBundle.string("browserTabLimit", fallback: "Close a tab before opening another.")
    }
    static var tabs: String {
        VyronResourceBundle.string("browserTabs", fallback: "Tabs")
    }
    static var unsavedPage: String {
        VyronResourceBundle.string("browserUnsavedPage", fallback: "Unsaved page")
    }
    static var unsupportedDownload: String {
        VyronResourceBundle.string("browserUnsupportedDownload", fallback: "Downloads are not supported in this browser. Open the website in your default browser to download.")
    }
    static var untitled: String {
        VyronResourceBundle.string("browserUntitled", fallback: "Untitled website")
    }
    static var verificationRequired: String {
        VyronResourceBundle.string("browserVerificationRequired", fallback: "This website requires human verification before it can be read.")
    }
    static var webPage: String {
        VyronResourceBundle.string("browserWebPage", fallback: "Website")
    }
}
