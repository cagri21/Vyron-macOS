import Foundation

public enum VyronProjectGuidanceError: Error, LocalizedError, Sendable, Equatable {
    case invalidRoot
    case unreadableFile
    case unsafeFile
    case oversizedFile
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidRoot:
            "The selected project folder could not be opened safely to read repository guidance."
        case .unreadableFile:
            "AGENTS.md or AGENTS.override.md could not be read safely. Check its permissions and symbolic links."
        case .unsafeFile:
            "Repository guidance must be a regular AGENTS.md or AGENTS.override.md file."
        case .oversizedFile:
            "Repository guidance exceeds the 32 KiB limit. Shorten AGENTS.md or AGENTS.override.md before retrying."
        case .invalidEncoding:
            "Repository guidance must be UTF-8 text without binary content."
        }
    }
}
