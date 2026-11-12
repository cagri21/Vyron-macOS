import Darwin
import Foundation

/// Opens every component without following links, including components of the selected skill directory.
struct VyronSkillResourceReader {
    static let maximumBytes = 65_536
    private static let credentialFiles: Set<String> = [
        "auth.json", "credentials", "credentials.json", "credentials.yaml", "credentials.yml", "credentials.toml",
        "secrets.json", "secrets.yaml", "secrets.yml", "secrets.toml", "token", "token.txt", "tokens.json",
        "api_key", "api-key", "api_key.txt", "api-key.txt", "id_rsa", "id_ed25519"
    ]

    func read(relativePath: String, directory: URL) throws -> String {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard directory.isFileURL, !relativePath.hasPrefix("/"), relativePath.utf8.count <= 2_048,
            !components.isEmpty, components.allSatisfy({
                !$0.isEmpty && !$0.hasPrefix(".") && !$0.contains("\0") && !$0.contains("\\")
                    && !Self.credentialFiles.contains($0.lowercased())
                    && !["pem", "key", "p12", "pfx"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
            })
        else { throw VyronSkillActivationError.unavailableDocument }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw VyronSkillActivationError.unavailableDocument }
        defer { Darwin.close(descriptor) }
        let directories = directory.standardizedFileURL.pathComponents.dropFirst() + components.dropLast()
        for component in directories {
            let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
            guard next >= 0 else { throw VyronSkillActivationError.unavailableDocument }
            Darwin.close(descriptor)
            descriptor = next
        }
        guard let name = components.last else { throw VyronSkillActivationError.unavailableDocument }
        let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw VyronSkillActivationError.unavailableDocument }
        defer { Darwin.close(file) }
        var information = stat()
        guard fstat(file, &information) == 0, information.st_mode & S_IFMT == S_IFREG else {
            throw VyronSkillActivationError.unavailableDocument
        }
        // FileHandle does not own the descriptor; the defer above closes it on every outcome.
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        let bytes = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard bytes.count <= Self.maximumBytes else { throw VyronSkillActivationError.truncatedDocument }
        guard let text = String(data: bytes, encoding: .utf8), !text.contains("\0") else {
            throw VyronSkillActivationError.invalidDocument
        }
        return text
    }
}
