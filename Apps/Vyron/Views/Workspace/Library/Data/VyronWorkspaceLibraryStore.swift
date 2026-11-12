import Foundation

struct VyronWorkspaceLibraryStore {
    let directory: URL

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        self.directory = directory ?? support.appendingPathComponent("VyronAI/WorkspaceLibrary", isDirectory: true)
    }

    private var manifestURL: URL { directory.appendingPathComponent("library.json") }

    func load() throws -> VyronWorkspaceLibrarySnapshot {
        try validateStorage()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return VyronWorkspaceLibrarySnapshot()
        }
        let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= VyronWorkspaceLibraryLimits.manifestBytes else { throw CocoaError(.coderInvalidValue) }
        let snapshot = try JSONDecoder().decode(
            VyronWorkspaceLibrarySnapshot.self, from: Data(contentsOf: manifestURL)
        )
        try validate(snapshot)
        return snapshot
    }

    func save(_ snapshot: VyronWorkspaceLibrarySnapshot) throws {
        try validateStorage()
        try validate(snapshot)
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= VyronWorkspaceLibraryLimits.manifestBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func validatedWebsite(_ address: String) -> URL? {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            let url = components.url
        else { return nil }
        return url
    }

    private func validateStorage() throws {
        for url in [directory, manifestURL] {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw CocoaError(.fileReadNoPermission)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                continue
            }
        }
    }

    private func validate(_ snapshot: VyronWorkspaceLibrarySnapshot) throws {
        guard snapshot.version == 1,
            Set(snapshot.pages.map(\.id)).count == snapshot.pages.count,
            Set(snapshot.links.map(\.id)).count == snapshot.links.count,
            Set(snapshot.recents.map(\.id)).count == snapshot.recents.count,
            snapshot.recents.count <= VyronWorkspaceLibraryLimits.recentItems,
            snapshot.pages.allSatisfy({
                $0.title.count <= VyronWorkspaceLibraryLimits.titleCharacters
                    && $0.body.utf8.count <= VyronWorkspaceLibraryLimits.pageBodyBytes
                    && $0.updatedAt.timeIntervalSinceReferenceDate.isFinite
            }),
            snapshot.links.allSatisfy({
                !$0.title.isEmpty && $0.title.count <= VyronWorkspaceLibraryLimits.titleCharacters
                    && Self.validatedWebsite($0.url.absoluteString) != nil
            }),
            snapshot.recents.allSatisfy({ validRecent($0, snapshot: snapshot) })
        else { throw CocoaError(.coderInvalidValue) }
    }

    private func validRecent(_ item: VyronWorkspaceRecentItem, snapshot: VyronWorkspaceLibrarySnapshot) -> Bool {
        guard item.openedAt.timeIntervalSinceReferenceDate.isFinite,
            !item.title.isEmpty, item.title.count <= VyronWorkspaceLibraryLimits.titleCharacters
        else { return false }
        switch item.kind {
        case .file:
            return item.url.isFileURL && item.id == "file:\(item.url.standardizedFileURL.path)"
        case .link:
            return Self.validatedWebsite(item.url.absoluteString) != nil
                && snapshot.links.contains { "link:\($0.id.uuidString)" == item.id && $0.url == item.url }
        case .page:
            return snapshot.pages.contains {
                "page:\($0.id.uuidString)" == item.id && item.url.absoluteString == "vyron-page://\($0.id.uuidString)"
            }
        }
    }
}
