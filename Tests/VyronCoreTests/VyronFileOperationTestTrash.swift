import Foundation
import VyronDevelopment

struct VyronFileOperationTestTrash: VyronProjectFileTrashing {
    let destination: URL
    let failure: VyronFileOperationTestTrashFailure
    var observe: (@Sendable (URL) throws -> Void)? = nil

    func trashItem(at url: URL) throws -> URL? {
        try observe?(url)
        if failure == .beforeMove { throw DevelopmentError("The fake native Trash action failed before moving.") }
        try FileManager.default.moveItem(at: url, to: destination)
        if failure == .afterMove { throw DevelopmentError("The fake native Trash action lost its acknowledgment.") }
        return destination
    }
}
