import CoreFoundation
import Foundation
import OSLog

enum VyronInstalledApplicationCatalog {
    private static let logger = Logger(subsystem: "ai.vyron.desktop", category: "Installed applications")
    private static let directoryKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

    static var standardApplicationDirectories: [URL] {
        [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    static func applications(in directories: [URL] = standardApplicationDirectories) -> [VyronInstalledApplication] {
        var identifiers: Set<String> = []
        return directories.flatMap(applications(in:)).filter { identifiers.insert($0.id).inserted }
    }

    static func application(at url: URL) -> VyronInstalledApplication? {
        guard url.isFileURL, isApplicationURL(url) else { return nil }
        let bundleURL = URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
        guard let values = directoryValues(at: bundleURL), values.isDirectory == true, values.isSymbolicLink == false,
            let metadata = CFBundleCopyInfoDictionaryInDirectory(bundleURL as CFURL) as? [String: Any],
            metadata["CFBundlePackageType"] as? String == "APPL",
            let identifier = metadata[kCFBundleIdentifierKey as String] as? String, !identifier.isEmpty
        else { return nil }

        let name = (Bundle(url: bundleURL)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (metadata["CFBundleDisplayName"] as? String)
            ?? (metadata[kCFBundleNameKey as String] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return VyronInstalledApplication(id: identifier, name: name, url: bundleURL)
    }

    private static func applications(in directory: URL) -> [VyronInstalledApplication] {
        let files = FileManager.default
        guard directory.isFileURL, files.fileExists(atPath: directory.path),
            let values = directoryValues(at: directory), values.isDirectory == true, values.isSymbolicLink == false,
            let enumerator = files.enumerator(
                at: directory, includingPropertiesForKeys: Array(directoryKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
                    logger.debug("Application enumeration skipped entry with error \((error as NSError).code).")
                    return true
                }
            )
        else { return [] }

        var applications: [VyronInstalledApplication] = []
        for case let url as URL in enumerator {
            guard let values = directoryValues(at: url), values.isSymbolicLink == false else {
                enumerator.skipDescendants()
                continue
            }
            guard isApplicationURL(url) else { continue }
            enumerator.skipDescendants()
            if let application = application(at: url) { applications.append(application) }
        }
        return applications.sorted {
            let firstDepth = $0.url.pathComponents.count
            let secondDepth = $1.url.pathComponents.count
            return firstDepth == secondDepth ? $0.url.path < $1.url.path : firstDepth < secondDepth
        }
    }

    private static func isApplicationURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func directoryValues(at url: URL) -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: directoryKeys)
        } catch {
            logger.debug("Application directory metadata was unavailable with error \((error as NSError).code).")
            return nil
        }
    }
}
