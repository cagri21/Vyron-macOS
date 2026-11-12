import Foundation

public enum SidebarOrganizationError: Error, LocalizedError, Sendable, Equatable {
    case invalidFolderName
    case invalidProjectName
    case invalidSourceFolders
    case duplicateFolderName
    case folderNotFound
    case folderCycle
    case invalidProjectPath
    case invalidOrganization(String)
    case unreadableStore(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            "Use a folder name between 1 and 80 characters without line breaks or control characters."
        case .invalidProjectName:
            "Use a project name between 1 and 80 characters without line breaks or control characters."
        case .invalidSourceFolders:
            "Choose between 1 and 16 unique source folders with valid absolute local paths."
        case .duplicateFolderName: "A folder with this name already exists in that location."
        case .folderNotFound: "The sidebar folder no longer exists."
        case .folderCycle: "A folder cannot be moved inside itself or one of its children."
        case .invalidProjectPath: "The project must have a valid absolute local path."
        case .invalidOrganization(let detail): "The sidebar organization is invalid. \(detail)"
        case .unreadableStore(let detail):
            "The saved sidebar could not be read. Its original file has been preserved and cannot be overwritten. \(detail)"
        case .writeFailed(let detail): "The sidebar could not be saved. \(detail)"
        }
    }
}
