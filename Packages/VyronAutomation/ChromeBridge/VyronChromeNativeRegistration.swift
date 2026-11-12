import Foundation

public enum VyronChromeNativeRegistration {
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
        let nativeDirectory = home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true
        )
        let destination = try VyronChromeBridgeDirectory.open(nativeDirectory, create: true, privateDirectory: false)
        let manifest = VyronChromeNativeManifest(path: host.path, origin: "chrome-extension://\(extensionID)/")
        try destination.write("ai.vyron.chrome.json", data: VyronChromeBridgePolicy.encode(manifest), replacing: true)
    }
}
