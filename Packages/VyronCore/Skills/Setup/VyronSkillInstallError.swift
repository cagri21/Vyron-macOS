import Foundation

public enum VyronSkillInstallError: Error, LocalizedError, Sendable, Equatable {
    case invalidIdentifier
    case invalidPackage
    case unsafePath
    case packageTooLarge
    case destinationConflict

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            "The skill identifier must be a lowercase name containing letters, numbers, and hyphens."
        case .invalidPackage:
            "The skill package is missing a valid SKILL.md document or contains an unsupported file."
        case .unsafePath:
            "The skill package or installation path contains an unsafe path or symbolic link."
        case .packageTooLarge:
            "The skill package exceeds the supported file, size, or directory limits."
        case .destinationConflict:
            "A different version of this skill already exists. The existing files were preserved."
        }
    }
}
