import CryptoKit
import Darwin
import Foundation

/// Held directory descriptors prevent traversal through project-controlled links.
final class VyronProjectFileAccess {
    let rootURL: URL
    private let rootDescriptor: Int32
    private let isAllowedComponent: @Sendable (String) -> Bool

    init(rootURL: URL, isAllowedComponent: @escaping @Sendable (String) -> Bool) throws {
        let descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The project folder could not be opened safely.") }
        self.rootURL = rootURL
        rootDescriptor = descriptor
        self.isAllowedComponent = isAllowedComponent
    }

    deinit { close(rootDescriptor) }

    func normalized(_ request: VyronProjectFileOperationRequest) throws -> VyronProjectFileOperationRequest {
        if case .rename(let rename) = request {
            guard !rename.newName.contains("/"), isAllowedComponent(rename.newName) else {
                throw DevelopmentError("Choose one safe filename, without a folder path.")
            }
        }
        let source = try parent(request.paths.sourcePath)
        let descriptor = openat(source.descriptor, source.leaf, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The source is missing or is a symbolic link.") }
        defer { close(descriptor) }
        let sourcePath = try relativePath(descriptor)
        guard let proposedDestination = request.paths.destinationPath else {
            return .trash(VyronProjectFileTrashRequest(path: sourcePath))
        }
        let destination = try parent(proposedDestination)
        let parentPath = try relativePath(destination.descriptor, allowRoot: true)
        let destinationPath = parentPath.isEmpty ? destination.leaf : parentPath + "/" + destination.leaf
        guard sourcePath != destinationPath, !destinationPath.hasPrefix(sourcePath + "/") else {
            throw DevelopmentError("Choose a different destination outside the source folder.")
        }
        try requireAbsent(destination)
        switch request {
        case .move:
            return .move(VyronProjectFileMoveRequest(sourcePath: sourcePath, destinationPath: destinationPath))
        case .rename:
            return .rename(VyronProjectFileRenameRequest(path: sourcePath, newName: destination.leaf))
        case .trash:
            throw DevelopmentError("The Trash request has an unexpected destination.")
        }
    }

    func snapshot(_ request: VyronProjectFileOperationRequest) throws -> VyronProjectFileSnapshot {
        try Task.checkCancellation()
        try validateRoot()
        let source = try parent(request.paths.sourcePath)
        let descriptor = openat(source.descriptor, source.leaf, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The source is missing or is a symbolic link.") }
        defer { close(descriptor) }
        var entries: [VyronProjectFileEntrySnapshot] = []
        var contentBytes = 0
        try collect(descriptor, relativePath: "", entries: &entries, contentBytes: &contentBytes)
        let destinationIdentity: VyronProjectFileIdentity?
        if let path = request.paths.destinationPath {
            let destination = try parent(path)
            try requireAbsent(destination)
            destinationIdentity = try identity(destination.descriptor)
        } else {
            destinationIdentity = nil
        }
        return VyronProjectFileSnapshot(
            entries: entries, sourceParent: try identity(source.descriptor), destinationParent: destinationIdentity,
            isCaseSensitive: try rootURL.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
            ).volumeSupportsCaseSensitiveNames ?? true
        )
    }

    func move(_ prepared: VyronPreparedProjectFileOperation) throws {
        guard let destinationPath = prepared.destinationPath else {
            throw DevelopmentError("Choose a destination for this file move.")
        }
        let source = try parent(prepared.sourcePath)
        let destination = try parent(destinationPath)
        try requireAbsent(destination)
        var current = stat()
        guard fstatat(source.descriptor, source.leaf, &current, AT_SYMLINK_NOFOLLOW) == 0,
            Self.identity(current) == prepared.snapshot.entries.first?.identity else {
            throw DevelopmentError("The source changed after review. Inspect it before trying again.")
        }
        try Task.checkCancellation()
        guard renameatx_np(
            source.descriptor, source.leaf, destination.descriptor, destination.leaf, UInt32(RENAME_EXCL)
        ) == 0 else {
            throw DevelopmentError("The item was not moved. Its destination may now exist; no item was overwritten.")
        }
    }

    func sourceMatchesIdentity(_ path: String, identity: VyronProjectFileIdentity) throws -> Bool {
        let source = try parent(path)
        var info = stat()
        if fstatat(source.descriptor, source.leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            return UInt64(bitPattern: Int64(info.st_dev)) == identity.device && UInt64(info.st_ino) == identity.inode
        }
        guard errno == ENOENT else { throw DevelopmentError("The source outcome could not be inspected safely.") }
        return false
    }

    func stage(
        _ operation: VyronPreparedProjectFileOperation,
        in staging: VyronProjectFileStaging
    ) throws -> VyronProjectFileParent {
        try validateRoot()
        let source = try parent(operation.sourcePath)
        var current = stat()
        guard fstatat(source.descriptor, source.leaf, &current, AT_SYMLINK_NOFOLLOW) == 0,
            Self.identity(current) == operation.snapshot.entries.first?.identity else {
            throw DevelopmentError("The source changed after review. No item was sent to Trash.")
        }
        try Task.checkCancellation()
        guard renameatx_np(
            source.descriptor, source.leaf, staging.descriptor, staging.leaf, UInt32(RENAME_EXCL)
        ) == 0 else {
            throw DevelopmentError("The source could not be staged safely for Trash. It was preserved.")
        }
        return source
    }

    func validateStaged(
        _ operation: VyronPreparedProjectFileOperation,
        in staging: VyronProjectFileStaging
    ) throws {
        let descriptor = openat(staging.descriptor, staging.leaf, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The staged source changed or became a symbolic link.") }
        defer { close(descriptor) }
        var entries: [VyronProjectFileEntrySnapshot] = []
        var bytes = 0
        try collect(descriptor, relativePath: "", entries: &entries, contentBytes: &bytes)
        guard entries.count == operation.snapshot.entries.count,
            zip(entries, operation.snapshot.entries).allSatisfy({ current, original in
                current.relativePath == original.relativePath && current.isDirectory == original.isDirectory
                    && current.contentHash == original.contentHash
                    && current.identity.device == original.identity.device
                    && current.identity.inode == original.identity.inode
                    && current.identity.stableRevision == original.identity.stableRevision
            }) else {
            throw DevelopmentError("The source changed while entering private Trash staging.")
        }
    }

    func restoreStaged(
        _ operation: VyronPreparedProjectFileOperation,
        staging: VyronProjectFileStaging,
        originalParent: VyronProjectFileParent
    ) throws -> Bool {
        guard staging.containsItem() else { return false }
        try validateRoot()
        let expected = (operation.sourcePath as NSString).deletingLastPathComponent
        guard try relativePath(originalParent.descriptor, allowRoot: true) == expected else {
            throw DevelopmentError("The original folder moved; the item remains preserved in private staging.")
        }
        guard renameatx_np(
            staging.descriptor, staging.leaf, originalParent.descriptor, originalParent.leaf, UInt32(RENAME_EXCL)
        ) == 0 else {
            throw DevelopmentError("The original path is occupied; the item remains preserved in private staging.")
        }
        return true
    }

    private func parent(_ path: String) throws -> VyronProjectFileParent {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), path.utf8.count <= 4_096, !parts.isEmpty,
            parts.allSatisfy({ isAllowedComponent($0) && !$0.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }) }) else {
            throw DevelopmentError("Use a safe project-relative path, excluding the root, secrets and traversal.")
        }
        var descriptor = dup(rootDescriptor)
        guard descriptor >= 0 else { throw DevelopmentError("The project folder is unavailable.") }
        do {
            for component in parts.dropLast() {
                let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    throw DevelopmentError("A parent folder is missing or contains a symbolic link.")
                }
                close(descriptor)
                descriptor = next
            }
            return VyronProjectFileParent(descriptor: descriptor, leaf: parts[parts.count - 1])
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func requireAbsent(_ destination: VyronProjectFileParent) throws {
        var info = stat()
        guard fstatat(destination.descriptor, destination.leaf, &info, AT_SYMLINK_NOFOLLOW) != 0,
            errno == ENOENT else {
            throw DevelopmentError("The destination already exists or is unavailable. Existing items were preserved.")
        }
    }

    private func validateRoot() throws {
        guard try path(rootDescriptor) == rootURL.path else {
            throw DevelopmentError("The project folder moved. Reopen it before changing files.")
        }
        var current = stat()
        guard lstat(rootURL.path, &current) == 0, current.st_mode & S_IFMT == S_IFDIR else {
            throw DevelopmentError("The project folder is no longer available safely.")
        }
        let held = try identity(rootDescriptor)
        guard held.device == UInt64(bitPattern: Int64(current.st_dev)), held.inode == UInt64(current.st_ino) else {
            throw DevelopmentError("The project folder changed. Reopen it before changing files.")
        }
    }

    private func relativePath(_ descriptor: Int32, allowRoot: Bool = false) throws -> String {
        let actual = try path(descriptor)
        if allowRoot, actual == rootURL.path { return "" }
        let prefix = rootURL.path + "/"
        guard actual.hasPrefix(prefix) else { throw DevelopmentError("The item is outside the active project.") }
        return String(actual.dropFirst(prefix.count))
    }

    private func path(_ descriptor: Int32) throws -> String {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return -1 }
            return fcntl(descriptor, F_GETPATH, UnsafeMutableRawPointer(base))
        }
        guard result == 0 else { throw DevelopmentError("The held file path could not be inspected safely.") }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    private func identity(_ descriptor: Int32) throws -> VyronProjectFileIdentity {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw DevelopmentError("The item could not be inspected safely.") }
        return Self.identity(info)
    }

    private static func identity(_ info: stat) -> VyronProjectFileIdentity {
        let stableRevision = "\(info.st_mode):\(info.st_nlink):\(info.st_size):"
            + "\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
        let revision = stableRevision + ":\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        return VyronProjectFileIdentity(
            device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino),
            revision: SHA256.hash(data: Data(revision.utf8)).map { String(format: "%02x", $0) }.joined(),
            stableRevision: SHA256.hash(data: Data(stableRevision.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func collect(
        _ descriptor: Int32,
        relativePath: String,
        entries: inout [VyronProjectFileEntrySnapshot],
        contentBytes: inout Int
    ) throws {
        try Task.checkCancellation()
        guard entries.count < VyronProjectFileOperationLimits.maximumEntries,
            relativePath.split(separator: "/").count <= VyronProjectFileOperationLimits.maximumDepth else {
            throw DevelopmentError("The folder exceeds the bounded file-operation review allowance.")
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw DevelopmentError("The source could not be inspected.") }
        let before = Self.identity(info)
        let isDirectory = info.st_mode & S_IFMT == S_IFDIR
        guard isDirectory || info.st_mode & S_IFMT == S_IFREG else {
            throw DevelopmentError("Only regular files and folders can be moved or sent to Trash.")
        }
        let hash: String?
        if isDirectory {
            hash = nil
        } else {
            guard info.st_size >= 0,
                info.st_size <= VyronProjectFileOperationLimits.maximumContentBytes - contentBytes else {
                throw DevelopmentError("The contents exceed the bounded file-operation review allowance.")
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            var digest = SHA256()
            while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
                try Task.checkCancellation()
                contentBytes += data.count
                guard contentBytes <= VyronProjectFileOperationLimits.maximumContentBytes else {
                    throw DevelopmentError("The contents exceed the bounded file-operation review allowance.")
                }
                digest.update(data: data)
            }
            hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        entries.append(VyronProjectFileEntrySnapshot(
            relativePath: relativePath, isDirectory: isDirectory, identity: before, contentHash: hash
        ))
        if isDirectory {
            for name in try childNames(descriptor) {
                guard isAllowedComponent(name) || name == ".DS_Store" else {
                    throw DevelopmentError("The folder contains excluded files, secrets or generated folders.")
                }
                let child = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else {
                    throw DevelopmentError("The folder contains an unavailable item or symbolic link.")
                }
                if name == ".DS_Store" {
                    var metadata = stat()
                    guard fstat(child, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
                        close(child)
                        throw DevelopmentError("Finder metadata must be a regular file, not a folder or symbolic link.")
                    }
                }
                do {
                    try collect(
                        child, relativePath: relativePath.isEmpty ? name : relativePath + "/" + name,
                        entries: &entries, contentBytes: &contentBytes
                    )
                    close(child)
                } catch {
                    close(child)
                    throw error
                }
            }
        }
        guard try identity(descriptor) == before else {
            throw DevelopmentError("The source changed during inspection. Inspect it again before review.")
        }
    }

    private func childNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw DevelopmentError("The folder could not be inspected.") }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate)
            throw DevelopmentError("The folder could not be inspected.")
        }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
            guard names.count <= VyronProjectFileOperationLimits.maximumEntries else {
                throw DevelopmentError("The folder exceeds the bounded file-operation review allowance.")
            }
            errno = 0
        }
        guard errno == 0 else { throw DevelopmentError("The folder could not be inspected completely.") }
        return names.sorted()
    }
}
