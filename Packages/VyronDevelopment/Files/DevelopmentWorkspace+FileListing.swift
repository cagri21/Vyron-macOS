import Foundation

extension DevelopmentWorkspace {
    /// Keeps traversal and each returned page bounded while exposing paths beyond a single tool response.
    /// Filtering precedes the matching-file cap so documentation does not hide source matches.
    public func fileListing(_ requested: VyronDevelopmentFileListingRequest) throws -> VyronDevelopmentFileListingPage {
        try Task.checkCancellation()
        let request = try requested.validated()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys)
        ) else { throw DevelopmentError("The project could not be listed.") }
        let prefix = rootURL.path + "/"
        var files: [DevelopmentFile] = []
        var visited = 0
        var scanLimited = false
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            visited += 1
            if visited > VyronDevelopmentFileListingLimits.maximumVisitedEntries
                || files.count >= VyronDevelopmentFileListingLimits.maximumInventoryFiles {
                scanLimited = true
                break
            }
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if !Self.allowedComponent(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, Self.allowedComponent(url.lastPathComponent),
                url.path.hasPrefix(prefix),
                (values.fileSize ?? 0) <= VyronDevelopmentFileReadBudget.maximumFileBytes else { continue }
            let path = String(url.path.dropFirst(prefix.count))
            if let query = request.query, !path.localizedCaseInsensitiveContains(query) { continue }
            files.append(DevelopmentFile(path: path, size: Int64(values.fileSize ?? 0)))
        }
        try Task.checkCancellation()
        let ordered = files.sorted(by: VyronDevelopmentFileListingOrder.precedes)
        let page = Array(ordered.dropFirst(request.offset).prefix(request.limit))
        let next = request.offset + page.count
        return VyronDevelopmentFileListingPage(
            files: page,
            coverage: VyronDevelopmentFileListingCoverage(
                offset: request.offset,
                nextOffset: next < ordered.count ? next : nil,
                totalMatches: ordered.count,
                scanLimited: scanLimited
            )
        )
    }
}
