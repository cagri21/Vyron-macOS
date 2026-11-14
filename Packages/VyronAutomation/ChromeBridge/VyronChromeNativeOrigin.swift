import Foundation

enum VyronChromeNativeOrigin {
    static func validate(origin: String, executable: String, home: URL) throws -> String {
        guard let parts = URLComponents(string: origin), parts.scheme == "chrome-extension",
            let id = parts.host, id.count == 32,
            id.allSatisfy({ ("a"..."p").contains(String($0)) }),
            origin == "chrome-extension://\(id)/", executable.hasPrefix("/"),
            URL(fileURLWithPath: executable).standardizedFileURL.path == executable
        else { throw VyronChromeBridgeError.invalidOrigin }
        guard let data = try registration(home: home) else {
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

    private static func registration(home: URL) throws -> Data? {
        // macOS can restrict this helper from reading Chrome's app data. Chrome still checks its own manifest.
        let location = VyronChromeNativeRegistration.privateDirectory(home: home)
        if FileManager.default.fileExists(atPath: location.path) {
            let directory = try VyronChromeBridgeDirectory.open(location, create: false)
            if let data = try directory.read(VyronChromeNativeRegistration.registrationName) { return data }
        }

        // Existing installations can keep using their original manifest until they register again.
        let chromeLocation = VyronChromeNativeRegistration.chromeDirectory(home: home)
        let directory = try VyronChromeBridgeDirectory.open(chromeLocation, create: false, privateDirectory: false)
        return try directory.read(VyronChromeNativeRegistration.manifestName)
    }
}
