import Foundation

public enum VyronMacPreviewError: Error, Sendable {
    case permissionRequired
    case applicationUnavailable
    case windowUnavailable
    case encodingFailed
}
