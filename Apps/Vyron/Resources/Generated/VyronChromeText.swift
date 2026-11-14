// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronChromeText {
    static var extensionID: String {
        VyronResourceBundle.string("chromeExtensionID", fallback: "Chrome extension ID")
    }
    static var hostUpdateRequired: String {
        VyronResourceBundle.string("chromeHostUpdateRequired", fallback: "Update and reconnect the Vyron Chrome helper to open tab groups.")
    }
    static var install: String {
        VyronResourceBundle.string("chromeInstall", fallback: "Enable Chrome connection")
    }
    static var installed: String {
        VyronResourceBundle.string("chromeInstalled", fallback: "Connection enabled. In Chrome, open the Vyron extension and choose Connect this tab.")
    }
    static var invalidID: String {
        VyronResourceBundle.string("chromeInvalidID", fallback: "Paste the 32-letter extension ID shown at chrome://extensions.")
    }
    static var missingHost: String {
        VyronResourceBundle.string("chromeMissingHost", fallback: "Open a packaged Vyron app that includes the Chrome helper, then try again.")
    }
    static var refresh: String {
        VyronResourceBundle.string("chromeRefresh", fallback: "Refresh connection")
    }
    static func sessions(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "chromeSessions",
            fallback: "Connected sessions: %d",
            arguments: [p1]
        )
    }
    static var setup: String {
        VyronResourceBundle.string("chromeSetup", fallback: "Load the Vyron extension in Chrome’s developer mode, then paste its extension ID here to enable the local connection.")
    }
    static var title: String {
        VyronResourceBundle.string("chromeTitle", fallback: "Chrome extension")
    }
    static var unsafePath: String {
        VyronResourceBundle.string("chromeUnsafePath", fallback: "The Chrome connection path contains a symbolic link. Choose a regular app and Chrome profile location.")
    }
    static var workHint: String {
        VyronResourceBundle.string("chromeWorkHint", fallback: "In Work, ask Vyron to open websites in a Chrome tab group or read a connected tab. Approve browser actions in the Chrome popup. Only tabs you connect can share page content with your model. Plan mode can only read.")
    }
}
