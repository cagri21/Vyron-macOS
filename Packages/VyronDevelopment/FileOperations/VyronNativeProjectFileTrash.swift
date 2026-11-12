import Foundation

public struct VyronNativeProjectFileTrash: VyronProjectFileTrashing {
    public init() {}

    public func trashItem(at url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }
}
