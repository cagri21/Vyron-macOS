import Darwin
import Foundation

actor VyronFolderAttachmentLoader {
    func load(_ url: URL) async throws -> VyronFolderAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronFolderAttachmentError.invalidFolder }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard VyronFolderAttachmentPolicy.allowsRoot(url) else {
            throw VyronFolderAttachmentError.invalidFolder
        }
        let root = try rootDescriptor(for: url)
        defer { close(root) }
        var scan = VyronFolderAttachmentScan()
        try scan.scan(directory: root, path: "", depth: 0)
        try Task.checkCancellation()
        let name = url.lastPathComponent
        return VyronFolderAttachment(id: UUID(), name: name, context: scan.context(name: name), summary: scan.summary)
    }

    private func rootDescriptor(for url: URL) throws -> Int32 {
        var expected = stat()
        guard lstat(url.path, &expected) == 0, expected.st_mode & S_IFMT == S_IFDIR else {
            throw VyronFolderAttachmentError.invalidFolder
        }
        let original = url.standardizedFileURL.path
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        // macOS uses these system aliases for temporary folders; user-created ancestry links remain excluded.
        let isSystemAlias = (original.hasPrefix("/var/") || original.hasPrefix("/tmp/"))
            && canonical.path == "/private" + original
        guard original == canonical.path || isSystemAlias else {
            throw VyronFolderAttachmentError.invalidFolder
        }
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        var descriptor = open("/", flags)
        guard descriptor >= 0 else { throw VyronFolderAttachmentError.invalidFolder }
        do {
            for component in canonical.pathComponents.dropFirst() {
                try Task.checkCancellation()
                let next = openat(descriptor, component, flags)
                guard next >= 0 else { throw VyronFolderAttachmentError.invalidFolder }
                close(descriptor)
                descriptor = next
            }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, opened.st_dev == expected.st_dev,
                opened.st_ino == expected.st_ino else {
                throw VyronFolderAttachmentError.invalidFolder
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }
}
