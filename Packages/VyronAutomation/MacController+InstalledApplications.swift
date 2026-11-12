import AppKit
import Foundation

extension MacController {
    func installedApplicationURL(for applicationID: String) -> URL? {
        let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationID)
        guard VyronXcodeApplicationCatalog.applicationIDs.contains(applicationID) else { return registeredURL }
        let xcodeURL = registeredURL == nil
            ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: VyronXcodeApplicationCatalog.xcodeID)
            : nil
        return VyronXcodeApplicationCatalog.applicationURL(
            for: applicationID,
            registeredURL: registeredURL,
            xcodeURL: xcodeURL
        )
    }
}
