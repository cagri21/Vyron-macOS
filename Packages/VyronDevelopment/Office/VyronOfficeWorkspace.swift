import Darwin
import Foundation

/// Binary Office input and exclusive artifact publication stay separate from source-edit history.
/// Descriptor-relative access refuses symbolic links and cannot overwrite an existing output.
public struct VyronOfficeWorkspace: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) { self.rootURL = rootURL }

    public func snapshot(path: String) throws -> Data {
        try Task.checkCancellation()
        let parent = try parentDescriptor(path)
        defer { close(parent.descriptor) }
        let descriptor = openat(parent.descriptor, parent.leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw failure("Choose a regular Office file inside this project.") }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
            metadata.st_size >= 0, metadata.st_size <= VyronOfficeLimits.maximumInputBytes
        else { throw failure("Office inputs must be regular files no larger than 64 MiB.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try file.read(upToCount: VyronOfficeLimits.maximumInputBytes + 1) ?? Data()
        guard data.count <= VyronOfficeLimits.maximumInputBytes else {
            throw failure("The Office input grew beyond 64 MiB.")
        }
        try Task.checkCancellation()
        return data
    }

    public func validateDestination(path: String) throws {
        let parent = try parentDescriptor(path)
        defer { close(parent.descriptor) }
        try requireMissing(parent: parent.descriptor, leaf: parent.leaf)
    }

    public func publish(_ publication: VyronOfficePublication) throws -> [String] {
        try Task.checkCancellation()
        let files = publication.artifacts
        guard !files.isEmpty, files.count <= VyronOfficeLimits.maximumPages,
            publication.isDirectory || files.count == 1,
            files.allSatisfy({ Self.allowedComponent($0.name) && !$0.name.contains("/") && !$0.data.isEmpty }),
            Set(files.map(\.name)).count == files.count,
            files.reduce(0, { $0 + $1.data.count }) <= VyronOfficeLimits.maximumOutputBytes
        else { throw failure("The Office engine returned invalid or oversized output.") }
        let destination = try parentDescriptor(publication.path)
        let parent = destination.descriptor
        let leaf = destination.leaf
        defer { close(parent) }
        try requireMissing(parent: parent, leaf: leaf)
        let temporary = ".vyron-office-" + UUID().uuidString
        if publication.isDirectory {
            try publishDirectory(files, parent: parent, temporary: temporary, destination: leaf)
            return files.map { publication.path + "/" + $0.name }
        }
        defer { _ = unlinkat(parent, temporary, 0) }
        try write(files[0].data, parent: parent, leaf: temporary)
        try Task.checkCancellation()
        guard renameatx_np(parent, temporary, parent, leaf, UInt32(RENAME_EXCL)) == 0 else {
            throw failure("The output destination changed or already exists. Existing files were preserved.")
        }
        return [publication.path]
    }

    private func publishDirectory(
        _ files: [VyronOfficeArtifact], parent: Int32, temporary: String, destination: String
    ) throws {
        guard mkdirat(parent, temporary, 0o700) == 0 else { throw failure("Could not prepare the preview folder.") }
        let directory = openat(parent, temporary, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else {
            _ = unlinkat(parent, temporary, AT_REMOVEDIR)
            throw failure("Could not open the preview folder safely.")
        }
        var published = false
        defer {
            if !published { for file in files { _ = unlinkat(directory, file.name, 0) } }
            close(directory)
            if !published { _ = unlinkat(parent, temporary, AT_REMOVEDIR) }
        }
        for file in files {
            try Task.checkCancellation()
            try write(file.data, parent: directory, leaf: file.name)
        }
        try Task.checkCancellation()
        guard renameatx_np(parent, temporary, parent, destination, UInt32(RENAME_EXCL)) == 0 else {
            throw failure("The preview destination changed or already exists. Existing files were preserved.")
        }
        published = true
    }

    private func write(_ data: Data, parent: Int32, leaf: String) throws {
        let descriptor = openat(parent, leaf, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw failure("An Office output could not be created exclusively.") }
        defer { close(descriptor) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(descriptor) == 0 else { throw failure("The Office output could not be saved completely.") }
    }

    private func requireMissing(parent: Int32, leaf: String) throws {
        var metadata = stat()
        guard fstatat(parent, leaf, &metadata, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw failure("Choose a new output path. Office processing never replaces an existing file or folder.")
        }
    }

    private func parentDescriptor(_ path: String) throws -> VyronOfficeParent {
        guard !path.hasPrefix("/"), path.utf8.count <= 4_096 else {
            throw failure("Use a relative Office path inside the selected project.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(Self.allowedComponent) else {
            throw failure("Hidden, secret, generated and parent-directory paths cannot be used for Office processing.")
        }
        var descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure("The selected project folder is unavailable.") }
        do {
            for part in parts.dropLast() {
                let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    throw failure("The parent folder must already exist inside this project and contain no symbolic links.")
                }
                close(descriptor)
                descriptor = next
            }
            guard let leaf = parts.last else { throw failure("Choose an Office file path.") }
            return VyronOfficeParent(descriptor: descriptor, leaf: leaf)
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func allowedComponent(_ value: String) -> Bool {
        let lower = value.lowercased()
        let excluded: Set<String> = [
            "node_modules", "vendor", "pods", "carthage", "build", "dist", "deriveddata", "__pycache__",
            "venv", "target", "secrets", "credentials", "credentials.json", "secrets.json", "auth.json", "tokens.json"
        ]
        return !value.isEmpty && !value.hasPrefix(".") && !value.contains("/")
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !excluded.contains(lower) && !lower.hasPrefix("credentials.") && !lower.hasPrefix("secrets.")
    }

    private func failure(_ message: String) -> DevelopmentError { DevelopmentError(message) }
}
