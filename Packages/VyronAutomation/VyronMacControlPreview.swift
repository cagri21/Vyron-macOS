import CoreGraphics
import Foundation

/// An in-memory view of the one application being controlled, never sent to a model.
public struct VyronMacControlPreview: Sendable {
    public let applicationID: String
    public let capturedAt: Date
    public let screenFrame: CGRect
    public let imageData: Data

    public init(applicationID: String, capturedAt: Date, screenFrame: CGRect, imageData: Data) {
        self.applicationID = applicationID
        self.capturedAt = capturedAt
        self.screenFrame = screenFrame
        self.imageData = imageData
    }

    /// Converts a native target's top-left screen coordinates into the preview's unit space.
    public func unitRect(for target: CGRect) -> CGRect? {
        guard Self.isUsable(screenFrame), Self.isUsable(target) else { return nil }
        let visible = screenFrame.intersection(target)
        guard Self.isUsable(visible) else { return nil }
        return CGRect(
            x: (visible.minX - screenFrame.minX) / screenFrame.width,
            y: (visible.minY - screenFrame.minY) / screenFrame.height,
            width: visible.width / screenFrame.width,
            height: visible.height / screenFrame.height
        )
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0 && !frame.isNull && !frame.isInfinite
    }
}
