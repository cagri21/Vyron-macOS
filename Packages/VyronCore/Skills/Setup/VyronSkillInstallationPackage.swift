import Darwin
import Foundation

/// A bounded, inert snapshot: supporting scripts are copied as bytes and are never executed.
struct VyronSkillInstallationPackage: Equatable {
    private(set) var directories: [String] = []
    private(set) var files: [VyronSkillInstallationFile] = []
    private var totalBytes = 0

    static func read(directory: URL, identifier: String) throws -> Self {
        let descriptor = try VyronSkillInstallationFilesystem.openDirectory(directory)
        defer { Darwin.close(descriptor) }
        return try read(descriptor: descriptor, identifier: identifier)
    }

    static func read(descriptor: Int32, identifier: String) throws -> Self {
        var package = Self()
        try package.collect(in: descriptor, prefix: "")
        package.directories.sort()
        package.files.sort { $0.relativePath < $1.relativePath }
        guard let document = package.files.first(where: { $0.relativePath == "SKILL.md" }),
            let content = String(data: document.content, encoding: .utf8), !content.contains("\0"),
            content.replacingOccurrences(of: "\r\n", with: "\n").hasPrefix("---\n"),
            let metadata = VyronSkillMetadataParser().parse(content, fallbackName: identifier),
            metadata.name == identifier, !metadata.description.isEmpty
        else { throw VyronSkillInstallError.invalidPackage }
        return package
    }

    func write(to descriptor: Int32) throws {
        for directory in directories {
            try Task.checkCancellation()
            let child = try VyronSkillInstallationFilesystem.openRelativeDirectory(
                directory,
                in: descriptor,
                create: true
            )
            Darwin.close(child)
        }
        for file in files {
            try Task.checkCancellation()
            try VyronSkillInstallationFilesystem.write(file, in: descriptor)
        }
    }

    private mutating func collect(in descriptor: Int32, prefix: String) throws {
        for name in try VyronSkillInstallationFilesystem.entries(in: descriptor) {
            try Task.checkCancellation()
            guard directories.count + files.count < VyronSkillInstallationLimits.maximumEntries else {
                throw VyronSkillInstallError.packageTooLarge
            }
            let path = prefix.isEmpty ? name : prefix + "/" + name
            guard path.utf8.count <= VyronSkillInstallationLimits.maximumPathBytes,
                path.split(separator: "/").count <= VyronSkillInstallationLimits.maximumDepth
            else { throw VyronSkillInstallError.packageTooLarge }
            var information = stat()
            guard fstatat(descriptor, name, &information, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw VyronSkillInstallationFilesystem.fileError()
            }
            switch information.st_mode & S_IFMT {
            case S_IFDIR:
                let child = try VyronSkillInstallationFilesystem.openChildDirectory(name, in: descriptor)
                defer { Darwin.close(child) }
                directories.append(path)
                try collect(in: child, prefix: path)
            case S_IFREG:
                let limit = name == "SKILL.md"
                    ? VyronSkillResourceReader.maximumBytes : VyronSkillInstallationLimits.maximumFileBytes
                let content = try VyronSkillInstallationFilesystem.readFile(name, in: descriptor, limit: limit)
                guard totalBytes <= VyronSkillInstallationLimits.maximumPackageBytes - content.count else {
                    throw VyronSkillInstallError.packageTooLarge
                }
                totalBytes += content.count
                files.append(VyronSkillInstallationFile(relativePath: path, content: content))
            case S_IFLNK:
                throw VyronSkillInstallError.unsafePath
            default:
                throw VyronSkillInstallError.invalidPackage
            }
        }
    }
}
