import AppKit
import CoreFoundation
import Foundation

extension MacController {
    /// Resolves one app bundle selected by the user without expanding the installed application catalog.
    public func attachedApplication(at url: URL) -> DesktopApplication? {
        guard let application = Self.readAttachedApplication(at: url) else { return nil }
        let bundleURL = url.resolvingSymlinksInPath().standardizedFileURL
        let running = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && Self.matches($0, at: bundleURL, identifier: application.id)
        }
        return running.map(Self.descriptor) ?? application
    }

    public func launch(attachedApplicationAt url: URL, expectedApplicationID: String) async throws -> DesktopApplication {
        try Task.checkCancellation()
        guard let application = Self.readAttachedApplication(at: url), application.id == expectedApplicationID else {
            throw MacControlError.applicationUnavailable
        }
        let bundleURL = url.resolvingSymlinksInPath().standardizedFileURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = false
        let running: NSRunningApplication
        do {
            running = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            // Workspace errors can contain the local bundle path.
            throw MacControlError.applicationUnavailable
        }
        try Task.checkCancellation()
        guard Self.matches(running, at: bundleURL, identifier: expectedApplicationID) else {
            throw MacControlError.applicationUnavailable
        }
        return Self.descriptor(running)
    }

    private static func readAttachedApplication(at url: URL) -> DesktopApplication? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
            url.host?.isEmpty != false || url.host == "localhost"
        else { return nil }
        let bundleURL = URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
        let values = try? bundleURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        // Reading the directory directly avoids Bundle's cached metadata after an app is replaced.
        guard values?.isDirectory == true, values?.isSymbolicLink == false,
            let metadata = CFBundleCopyInfoDictionaryInDirectory(bundleURL as CFURL) as? [String: Any],
            let identifier = metadata[kCFBundleIdentifierKey as String] as? String, !identifier.isEmpty
        else { return nil }
        let name = (metadata["CFBundleDisplayName"] as? String)
            ?? (metadata[kCFBundleNameKey as String] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return DesktopApplication(id: identifier, name: name, bundleIdentifier: identifier, processIdentifier: 0)
    }

    private static func matches(_ application: NSRunningApplication, at url: URL, identifier: String) -> Bool {
        !application.isTerminated && application.bundleIdentifier == identifier
            && application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == url.path
    }
}
