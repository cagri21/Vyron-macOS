import Foundation

public struct VyronProjectFileOperationRecovery: Sendable {
    public let disposition: VyronProjectFileOperationDisposition
    public let result: VyronProjectFileOperationResult?
    public let recordedAt: Date
    public let preservedItemURL: URL?
}
