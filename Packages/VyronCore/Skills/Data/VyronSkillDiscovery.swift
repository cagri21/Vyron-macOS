import Darwin
import Foundation

/// Reads local skill documents as inert reference text. It does not load configuration or execute skill instructions.
public struct VyronSkillDiscovery: Sendable {
    private let limits: VyronSkillDiscoveryLimits
    private let excludedDirectories: Set<String> = ["assets", "scripts", "references", "node_modules", "__pycache__"]
    private let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]

    public init(limits: VyronSkillDiscoveryLimits = VyronSkillDiscoveryLimits()) {
        self.limits = limits
    }

    public func discover(in roots: [VyronSkillRoot]) throws -> VyronSkillInventory {
        let manager = FileManager.default
        var skills: [VyronLocalSkill] = []
        var issues: [VyronSkillDiscoveryIssue] = []
        var visited = Set<String>()
        var entryCount = 0
        var didReachLimit = false
        for root in roots {
            try Task.checkCancellation()
            let directory = root.directoryURL
            guard manager.fileExists(atPath: directory.path) else { continue }
            guard directory.isFileURL, !containsSymbolicLink(directory) else {
                issues.append(VyronSkillDiscoveryIssue(fileURL: directory, reason: .symbolicLink))
                continue
            }
            guard let enumerator = manager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: { url, _ in
                    issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .unreadable))
                    return true
                }
            ) else {
                issues.append(VyronSkillDiscoveryIssue(fileURL: directory, reason: .unreadable))
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                entryCount += 1
                if entryCount > limits.maximumEntries || skills.count >= limits.maximumSkills {
                    didReachLimit = true
                    break
                }
                let values: URLResourceValues
                do {
                    values = try url.resourceValues(forKeys: resourceKeys)
                } catch {
                    issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .unreadable))
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .symbolicLink))
                    continue
                }
                if values.isDirectory == true {
                    if shouldSkip(url) {
                        enumerator.skipDescendants()
                    } else if enumerator.level >= limits.maximumDepth {
                        enumerator.skipDescendants()
                        didReachLimit = true
                    }
                    continue
                }
                guard url.lastPathComponent == "SKILL.md", visited.insert(url.path).inserted else { continue }
                guard values.isRegularFile == true else {
                    issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .nonRegularFile))
                    continue
                }
                do {
                    let preview = try readPreview(at: url)
                    guard let preview else {
                        issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .invalidEncoding))
                        continue
                    }
                    guard let metadata = VyronSkillMetadataParser().parse(
                        preview.content,
                        fallbackName: url.deletingLastPathComponent().lastPathComponent
                    ) else {
                        issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .malformedMetadata))
                        continue
                    }
                    skills.append(VyronLocalSkill(metadata: metadata, root: root, fileURL: url, preview: preview))
                } catch {
                    issues.append(VyronSkillDiscoveryIssue(fileURL: url, reason: .unreadable))
                }
            }
            if entryCount > limits.maximumEntries || skills.count >= limits.maximumSkills { break }
        }
        return VyronSkillInventory(
            skills: skills.sorted {
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            },
            issues: issues,
            didReachLimit: didReachLimit
        )
    }

    func activationPreview(for skill: VyronLocalSkill) throws -> VyronSkillPreview {
        try Task.checkCancellation()
        let file = skill.fileURL.standardizedFileURL
        let root = skill.root.directoryURL.standardizedFileURL
        guard file.isFileURL, file.lastPathComponent == "SKILL.md",
            file.pathComponents.starts(with: root.pathComponents)
        else { throw VyronSkillActivationError.unavailableDocument }
        let content = try VyronSkillResourceReader().read(
            relativePath: "SKILL.md",
            directory: file.deletingLastPathComponent()
        )
        return VyronSkillPreview(content: content, isTruncated: false)
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return excludedDirectories.contains(name) || (name.hasPrefix(".") && name != ".system")
    }

    private func containsSymbolicLink(_ url: URL) -> Bool {
        var component = url
        while component.path != "/" {
            do {
                if try component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { return true }
            } catch {
                // Failure to inspect a path component must not turn into permission to follow it.
                return true
            }
            component.deleteLastPathComponent()
        }
        return false
    }

    private func readPreview(at url: URL) throws -> VyronSkillPreview? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw fileError() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG else {
            let error = fileError()
            Darwin.close(descriptor)
            throw error
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let bytes = try handle.read(upToCount: limits.maximumDocumentBytes + 1) ?? Data()
        try handle.close()
        let truncated = bytes.count > limits.maximumDocumentBytes
        var preview = Data(bytes.prefix(limits.maximumDocumentBytes))
        // A byte limit can cut a valid UTF-8 scalar. Remove only that incomplete suffix.
        for _ in 0...3 {
            if let content = String(data: preview, encoding: .utf8) {
                return VyronSkillPreview(content: content, isTruncated: truncated)
            }
            guard truncated, !preview.isEmpty else { return nil }
            preview.removeLast()
        }
        return nil
    }

    private func fileError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
