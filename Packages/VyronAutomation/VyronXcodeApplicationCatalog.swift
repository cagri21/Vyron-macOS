import Foundation

/// Resolves only the simulator tools bundled with an installed Xcode application.
enum VyronXcodeApplicationCatalog {
    static let xcodeID = "com.apple.dt.Xcode"
    static let simulatorID = "com.apple.iphonesimulator"
    static let deviceHubID = "com.apple.dt.Devices"
    static let applicationIDs: Set<String> = [simulatorID, deviceHubID]

    private static let relativeApplicationPaths = [
        simulatorID: [
            "Contents/Developer/Applications/Simulator.app",
            "Contents/Applications/Simulator.app"
        ],
        deviceHubID: [
            "Contents/Applications/DeviceHub.app",
            "Contents/Developer/Applications/DeviceHub.app"
        ]
    ]

    static func applicationURL(for applicationID: String, registeredURL: URL?, xcodeURL: URL?) -> URL? {
        if let registeredURL {
            return matchesApplication(at: registeredURL, identifier: applicationID) ? registeredURL : nil
        }
        guard let relativePaths = relativeApplicationPaths[applicationID],
            let xcodeURL, matchesApplication(at: xcodeURL, identifier: xcodeID)
        else { return nil }
        return relativePaths.lazy.map { xcodeURL.appendingPathComponent($0, isDirectory: true) }.first {
            matchesApplication(at: $0, identifier: applicationID)
        }
    }

    private static func matchesApplication(at url: URL, identifier: String) -> Bool {
        url.isFileURL && url.pathExtension == "app" && Bundle(url: url)?.bundleIdentifier == identifier
    }
}
