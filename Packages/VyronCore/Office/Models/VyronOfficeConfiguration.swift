import Foundation

public struct VyronOfficeConfiguration: Sendable, Equatable {
    public let pythonExecutable: String

    public init(pythonExecutable: String = "") { self.pythonExecutable = pythonExecutable }

    public func resolvedExecutable() throws -> URL {
        let value = pythonExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        let managed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VyronAI/OfficeRuntime/bin", isDirectory: true)
        let candidates = value.isEmpty
            ? [managed.appendingPathComponent("python3").path, managed.appendingPathComponent("python").path,
               "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] : [value]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
            path.hasPrefix("/"), path.utf8.count <= 4_096,
            !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw VyronOfficeError(message: Self.setupMessage) }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true,
            url.lastPathComponent.lowercased().hasPrefix("python")
        else { throw VyronOfficeError(message: Self.setupMessage) }
        // Preserve the selected venv path: resolving its executable symlink would bypass pyvenv.cfg.
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static let setupMessage =
        "Choose an installed Python executable in Settings → Plugins → Office processing. "
        + "It must include deepseek-harness-sdk and its separately prepared Office runtime. "
        + "Vyron does not download them automatically. Native PDF previews remain available."
}
