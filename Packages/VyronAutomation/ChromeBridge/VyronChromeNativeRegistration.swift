import Foundation

public enum VyronChromeNativeRegistration {
    static let manifestName = "ai.vyron.chrome.json"
    static let registrationName = "registration.json"

    /// Explicitly register one packaged host for one Chrome extension. Never opens Chrome or runs the helper.
    public static func register(extensionID: String, appURL: URL, home: URL) throws {
        guard extensionID.utf8.count == 32, extensionID.utf8.allSatisfy({ (97...112).contains($0) }),
            appURL.isFileURL, appURL.path.hasPrefix("/"), appURL.pathExtension.lowercased() == "app",
            appURL.standardizedFileURL.path == appURL.path
        else { throw VyronChromeBridgeError.invalidOrigin }
        let hostDirectory = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let packaged = try VyronChromeBridgeDirectory.open(hostDirectory, create: false, privateDirectory: false)
        try packaged.validateExecutable("VyronChromeHost")
        let host = hostDirectory.appendingPathComponent("VyronChromeHost")
        let destination = try VyronChromeBridgeDirectory.open(
            chromeDirectory(home: home), create: true, privateDirectory: false
        )
        let registration = try VyronChromeBridgeDirectory.open(privateDirectory(home: home), create: true)
        let manifest = VyronChromeNativeManifest(path: host.path, origin: "chrome-extension://\(extensionID)/")
        let data = try VyronChromeBridgePolicy.encode(manifest)
        try registration.write(registrationName, data: data, replacing: true)
        try destination.write(manifestName, data: data, replacing: true)
    }

    static func privateDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/VyronAI/ChromeBridge", isDirectory: true)
    }

    static func chromeDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
    }
}
