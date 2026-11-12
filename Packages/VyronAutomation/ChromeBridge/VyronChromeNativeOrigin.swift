import Foundation

enum VyronChromeNativeOrigin {
    static func validate(origin: String, executable: String, home: URL) throws -> String {
        guard let parts = URLComponents(string: origin), parts.scheme == "chrome-extension",
            let id = parts.host, id.count == 32,
            id.allSatisfy({ ("a"..."p").contains(String($0)) }),
            origin == "chrome-extension://\(id)/", executable.hasPrefix("/"),
            URL(fileURLWithPath: executable).standardizedFileURL.path == executable
        else { throw VyronChromeBridgeError.invalidOrigin }
        let location = home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        let directory = try VyronChromeBridgeDirectory.open(location, create: false, privateDirectory: false)
        guard let data = try directory.read("ai.vyron.chrome.json") else {
            throw VyronChromeBridgeError.invalidOrigin
        }
        let manifest = try VyronChromeBridgePolicy.decode(VyronChromeNativeManifest.self, from: data)
        guard manifest.name == "ai.vyron.chrome", manifest.type == "stdio", manifest.path == executable,
            manifest.allowed_origins == [origin]
        else { throw VyronChromeBridgeError.invalidOrigin }
        let packaged = try VyronChromeBridgeDirectory.open(
            URL(fileURLWithPath: executable).deletingLastPathComponent(), create: false, privateDirectory: false
        )
        try packaged.validateExecutable("VyronChromeHost")
        return id
    }
}
