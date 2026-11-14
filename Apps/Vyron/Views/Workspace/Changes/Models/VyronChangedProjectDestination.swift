import Foundation

struct VyronChangedProjectDestination: Sendable {
    let projectURL: URL
    let changedFileURLs: [URL]
    let opensInXcode: Bool

    private static let excludedFolders: Set<String> = [
        "build", "carthage", "deriveddata", "dist", "node_modules", "pods", "vendor"
    ]
    private static let maximumMetadataBytes = 16 * 1_024 * 1_024

    static func resolve(root: URL, changedPaths: [String]) -> Self? {
        guard root.isFileURL, isDirectory(root), let root = canonicalRoot(root) else { return nil }
        var visitedFiles = Set<URL>()
        let files = changedPaths.compactMap { changedFile($0, in: root) }.filter { visitedFiles.insert($0).inserted }
        guard let project = iOSProject(in: root, near: files) else {
            return Self(projectURL: root, changedFileURLs: [], opensInXcode: false)
        }
        let destination = workspace(for: project, in: root) ?? project
        return Self(projectURL: destination, changedFileURLs: files, opensInXcode: true)
    }

    private static func canonicalRoot(_ root: URL) -> URL? {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path != "/" else { return nil }
        return canonical
    }

    private static func changedFile(_ path: String, in root: URL) -> URL? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\0"),
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        let file = root.appendingPathComponent(path, isDirectory: false)
        guard isLocal(file, in: root), isRegularFile(file) else { return nil }
        return file
    }

    private static func iOSProject(in root: URL, near files: [URL]) -> URL? {
        let nearbyDirectories = Set(files.flatMap { enclosingDirectories(of: $0, in: root) } + [root])
            .sorted {
                let lhsDepth = $0.pathComponents.count
                let rhsDepth = $1.pathComponents.count
                return lhsDepth == rhsDepth ? $0.path < $1.path : lhsDepth > rhsDepth
            }
        if let editedProject = nearbyDirectories.first(where: { directory in
            directory.pathExtension.lowercased() == "xcodeproj"
                && isSearchable(directory.deletingLastPathComponent(), below: root)
                && isIOSProject(directory)
        }) {
            return editedProject
        }
        for directory in nearbyDirectories where isSearchable(directory, below: root) {
            if let project = packages(in: directory, withExtension: "xcodeproj").first(where: isIOSProject) {
                return project
            }
        }
        let nearbyProjects = childDirectories(of: root)
            .filter { isSearchable($0, below: root) }
            .flatMap { packages(in: $0, withExtension: "xcodeproj") }
            .filter(isIOSProject)
        return nearbyProjects.count == 1 ? nearbyProjects.first : nil
    }

    private static func isSearchable(_ directory: URL, below root: URL) -> Bool {
        directory.pathComponents.dropFirst(root.pathComponents.count).allSatisfy { component in
            let name = component.lowercased()
            return !name.hasPrefix(".") && !excludedFolders.contains(name)
                && !name.hasSuffix(".xcodeproj") && !name.hasSuffix(".xcworkspace")
        }
    }

    private static func isIOSProject(_ project: URL) -> Bool {
        let settingsURL = project.appendingPathComponent("project.pbxproj", isDirectory: false)
        guard let data = metadata(at: settingsURL, in: project) else { return false }
        do {
            let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let objects = (propertyList as? [String: Any])?["objects"] as? [String: [String: Any]] else {
                return false
            }
            return objects.values.contains { object in
                guard object["isa"] as? String == "XCBuildConfiguration",
                    let settings = object["buildSettings"] as? [String: Any] else { return false }
                return settings.keys.contains("IPHONEOS_DEPLOYMENT_TARGET")
                    || supportsIOS(settings["SDKROOT"]) || supportsIOS(settings["SUPPORTED_PLATFORMS"])
            }
        } catch {
            return false
        }
    }

    private static func supportsIOS(_ setting: Any?) -> Bool {
        let values = setting as? [String] ?? (setting as? String).map { [$0] } ?? []
        return values.flatMap { $0.split(whereSeparator: \.isWhitespace) }.contains { value in
            value == "iphoneos" || value == "iphonesimulator"
        }
    }

    private static func workspace(for project: URL, in root: URL) -> URL? {
        for directory in enclosingDirectories(of: project, in: root) {
            for workspace in packages(in: directory, withExtension: "xcworkspace") {
                let document = workspace.appendingPathComponent("contents.xcworkspacedata", isDirectory: false)
                guard let data = metadata(at: document, in: workspace) else { continue }
                do {
                    let xml = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
                    guard let element = xml.rootElement(), element.name == "Workspace" else { continue }
                    if contains(project, inside: element, relativeTo: directory, workspaceParent: directory) {
                        return workspace
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private static func contains(
        _ project: URL,
        inside element: XMLElement,
        relativeTo group: URL,
        workspaceParent: URL
    ) -> Bool {
        (element.children ?? []).contains { child in
            guard let child = child as? XMLElement,
                let location = child.attribute(forName: "location")?.stringValue,
                let separator = location.firstIndex(of: ":") else { return false }
            let path = String(location[location.index(after: separator)...])
            let url: URL
            switch location[..<separator] {
            case "group": url = group.appendingPathComponent(path)
            case "container": url = workspaceParent.appendingPathComponent(path)
            case "absolute": url = URL(fileURLWithPath: path)
            default: return false
            }
            if child.name == "FileRef" {
                return url.standardizedFileURL.path == project.path
            }
            return child.name == "Group"
                && contains(project, inside: child, relativeTo: url, workspaceParent: workspaceParent)
        }
    }

    private static func enclosingDirectories(of url: URL, in root: URL) -> [URL] {
        var directory = url.deletingLastPathComponent()
        var result: [URL] = []
        while directory.path == root.path || isLocal(directory, in: root) {
            result.append(directory)
            directory.deleteLastPathComponent()
        }
        return result
    }

    private static func packages(in directory: URL, withExtension extensionName: String) -> [URL] {
        childDirectories(of: directory).filter { $0.pathExtension.lowercased() == extensionName }
    }

    private static func childDirectories(of parent: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles
            ).filter { isLocal($0, in: parent) && isDirectory($0) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return []
        }
    }

    private static func metadata(at url: URL, in parent: URL) -> Data? {
        guard isLocal(url, in: parent) else { return nil }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= maximumMetadataBytes else {
                return nil
            }
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    private static func isLocal(_ url: URL, in directory: URL) -> Bool {
        url.path.hasPrefix(directory.path + "/") && url.resolvingSymlinksInPath().path == url.path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values.isDirectory == true && values.isSymbolicLink != true
        } catch {
            return false
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
        } catch {
            return false
        }
    }
}
