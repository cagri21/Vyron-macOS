import Darwin
import Foundation

/// Installs reviewed local packages. It does not download packages, install dependencies, or execute instructions.
public actor VyronSkillInstaller {
    public init() {}

    public func install(_ request: VyronSkillInstallRequest) throws -> URL {
        try Task.checkCancellation()
        try validateIdentifier(request.identifier)
        let package = try VyronSkillInstallationPackage.read(
            directory: request.packageDirectory,
            identifier: request.identifier
        )
        try Task.checkCancellation()
        let parent = try VyronSkillInstallationFilesystem.openDirectory(request.installationDirectory, create: true)
        defer { Darwin.close(parent) }
        let destination = request.installationDirectory.appendingPathComponent(request.identifier, isDirectory: true)
        if try existingMatches(request.identifier, in: parent, package: package) { return destination }

        let stagingName = ".vyron-skill-install-" + UUID().uuidString
        guard mkdirat(parent, stagingName, 0o700) == 0 else {
            throw VyronSkillInstallationFilesystem.fileError()
        }
        let staging: Int32
        do {
            staging = try VyronSkillInstallationFilesystem.openChildDirectory(stagingName, in: parent)
        } catch {
            // Without a verified descriptor, remove only the empty directory created above.
            guard unlinkat(parent, stagingName, AT_REMOVEDIR) == 0 else {
                throw VyronSkillInstallationFilesystem.fileError()
            }
            throw error
        }
        defer { Darwin.close(staging) }
        do {
            try package.write(to: staging)
            try Task.checkCancellation()
            // RENAME_EXCL keeps an existing or concurrently created skill intact.
            if renameatx_np(parent, stagingName, parent, request.identifier, UInt32(RENAME_EXCL)) == 0 {
                return destination
            }
            guard errno == EEXIST else { throw VyronSkillInstallationFilesystem.fileError() }
            guard try existingMatches(request.identifier, in: parent, package: package) else {
                throw VyronSkillInstallError.destinationConflict
            }
        } catch {
            // Cleanup errors propagate as well; cleanup never follows a replaced staging path.
            try VyronSkillInstallationFilesystem.removeStaging(stagingName, in: parent, descriptor: staging)
            throw error
        }
        try VyronSkillInstallationFilesystem.removeStaging(stagingName, in: parent, descriptor: staging)
        return destination
    }

    private func existingMatches(
        _ identifier: String,
        in parent: Int32,
        package: VyronSkillInstallationPackage
    ) throws -> Bool {
        guard try VyronSkillInstallationFilesystem.exists(identifier, in: parent) else { return false }
        let existing = try VyronSkillInstallationFilesystem.openChildDirectory(identifier, in: parent)
        defer { Darwin.close(existing) }
        let installed = try VyronSkillInstallationPackage.read(descriptor: existing, identifier: identifier)
        guard installed == package else { throw VyronSkillInstallError.destinationConflict }
        return true
    }

    private func validateIdentifier(_ identifier: String) throws {
        let bytes = Array(identifier.utf8)
        guard !bytes.isEmpty, bytes.count <= 64,
            bytes[0] >= 97, bytes[0] <= 122,
            bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
        else { throw VyronSkillInstallError.invalidIdentifier }
    }
}
