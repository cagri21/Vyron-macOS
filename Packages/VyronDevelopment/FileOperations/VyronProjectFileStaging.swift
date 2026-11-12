import Darwin
import Foundation

/// Private app-owned staging is outside the project and never exposed as an agent-writable path.
final class VyronProjectFileStaging {
    let descriptor: Int32
    let url: URL
    let leaf: String

    init(rootURL: URL, operationID: UUID, name: String) throws {
        let directoryURL = rootURL.appendingPathComponent(operationID.uuidString, isDirectory: true)
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("Private Trash staging is unavailable.") }
        do {
            for component in directoryURL.path.split(separator: "/").map(String.init) {
                var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT {
                    guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else {
                        throw DevelopmentError("Private Trash staging could not be created.")
                    }
                    next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else {
                    throw DevelopmentError("Private Trash staging contains an unavailable directory or symbolic link.")
                }
                close(descriptor)
                descriptor = next
            }
            self.descriptor = descriptor
            leaf = name
            url = directoryURL.appendingPathComponent(name)
        } catch {
            close(descriptor)
            throw error
        }
    }

    deinit { close(descriptor) }

    func requireSameVolume(as identity: VyronProjectFileIdentity) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, UInt64(bitPattern: Int64(info.st_dev)) == identity.device else {
            throw DevelopmentError("Trash requires private staging on the same volume. No project item was changed.")
        }
        guard !containsItem() else { throw DevelopmentError("The private Trash staging destination is occupied.") }
    }

    func containsItem() -> Bool {
        var info = stat()
        return fstatat(descriptor, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0
    }
}
