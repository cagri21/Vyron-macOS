import CoreGraphics
import VyronCore

enum VyronSidebarDropSurface {
    case entry(VyronSidebarEntry)
    case topLevel

    var id: String {
        switch self {
        case .entry(let entry): entry.id
        case .topLevel: "drop:topLevel"
        }
    }

    func destination(for source: VyronSidebarRow, verticalPosition: CGFloat) -> VyronSidebarDestination? {
        switch self {
        case .topLevel:
            let group: VyronSidebarGroup = switch source {
            case .folder: .rootFolders
            case .item(.project): .rootProjects
            case .item(.conversation): .rootChats
            }
            return VyronSidebarDestination(group: group, position: .end)
        case .entry(let entry):
            guard let group = entry.group else { return nil }
            guard let row = entry.row else { return VyronSidebarDestination(group: group, position: .end) }
            guard row != source else { return nil }

            let edge = VyronSidebarStyle.dropEdgeFraction
            if verticalPosition >= edge && verticalPosition < 1 - edge {
                switch (source, row) {
                case (_, .folder(let folder)):
                    return VyronSidebarDestination(group: .folder(folder), position: .end)
                case (.item(.conversation), .item(.project(let path))):
                    return VyronSidebarDestination(group: .project(.init(path: path)), position: .end)
                case (_, .item(.project)):
                    return nil
                default:
                    break
                }
            }
            let position: VyronSidebarInsertion = verticalPosition < 0.5 ? .before(row) : .after(row)
            return VyronSidebarDestination(group: group, position: position)
        }
    }
}
