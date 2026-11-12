import AppKit
import Foundation
import VyronAutomation

extension MacController: VyronMacWorkControlling {
    func openProject(_ url: URL) async throws -> DesktopApplication {
        let xcodeID = VyronMacWorkApplicationIDs.xcode
        guard let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: xcodeID),
            Bundle(url: xcodeURL)?.bundleIdentifier == xcodeID,
            url.isFileURL, ["xcodeproj", "xcworkspace"].contains(url.pathExtension.lowercased())
        else { throw MacControlError.applicationUnavailable }
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let running = try await NSWorkspace.shared.open(
            [url], withApplicationAt: xcodeURL, configuration: configuration
        )
        try Task.checkCancellation()
        guard running.bundleIdentifier == xcodeID, !running.isTerminated else {
            throw MacControlError.applicationUnavailable
        }
        return DesktopApplication(
            id: xcodeID, name: running.localizedName ?? "Xcode",
            bundleIdentifier: xcodeID, processIdentifier: running.processIdentifier
        )
    }
}
