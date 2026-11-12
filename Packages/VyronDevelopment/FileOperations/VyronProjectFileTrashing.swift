import Foundation

/// The native Trash boundary is replaceable in tests; it never permanently removes project contents.
public protocol VyronProjectFileTrashing: Sendable {
    func trashItem(at url: URL) throws -> URL?
}
