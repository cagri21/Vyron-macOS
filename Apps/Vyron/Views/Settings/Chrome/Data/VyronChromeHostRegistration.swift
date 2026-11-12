import Foundation
import VyronAutomation

enum VyronChromeHostRegistration {
    static func register(extensionID: String, appURL: URL, home: URL) throws {
        guard extensionID.count == 32, extensionID.utf8.allSatisfy({ (97...112).contains($0) }) else {
            throw VyronChromeSetupError.invalidExtensionID
        }
        let host = appURL.appendingPathComponent("Contents/MacOS/VyronChromeHost")
        guard host.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: host.path) else {
            throw VyronChromeSetupError.missingHost
        }
        try VyronChromeNativeRegistration.register(extensionID: extensionID, appURL: appURL, home: home)
    }
}
