import CoreGraphics

enum VyronComputerPointerGeometry {
    static func desktopFrame(for target: CGRect, primaryHeight: CGFloat, screens: [CGRect]) -> CGRect? {
        guard let target = appKitFrame(for: target, primaryHeight: primaryHeight) else { return nil }
        var bestDisplay: CGRect?
        var visibleTarget = CGRect.zero
        for screen in screens where isUsable(screen) {
            let visible = screen.intersection(target)
            guard isUsable(visible), visible.width * visible.height > visibleTarget.width * visibleTarget.height else {
                continue
            }
            bestDisplay = screen
            visibleTarget = visible
        }
        guard let bestDisplay else { return nil }
        let size = min(VyronComputerPreviewStyle.pointerSize, bestDisplay.width, bestDisplay.height)
        let center = clampedCenter(
            CGPoint(x: visibleTarget.midX, y: visibleTarget.midY), in: bestDisplay, markerSize: size
        )
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    static func appKitFrame(for target: CGRect, primaryHeight: CGFloat) -> CGRect? {
        guard isUsable(target), primaryHeight.isFinite, primaryHeight > 0 else { return nil }
        let frame = CGRect(x: target.minX, y: primaryHeight - target.maxY, width: target.width, height: target.height)
        return isUsable(frame) ? frame : nil
    }

    static func previewPoint(for unitFrame: CGRect, in imageFrame: CGRect) -> CGPoint {
        clampedCenter(
            CGPoint(
                x: imageFrame.minX + unitFrame.midX * imageFrame.width,
                y: imageFrame.minY + unitFrame.midY * imageFrame.height
            ),
            in: imageFrame,
            markerSize: VyronComputerPreviewStyle.pointerSize
        )
    }

    private static func clampedCenter(_ center: CGPoint, in bounds: CGRect, markerSize: CGFloat) -> CGPoint {
        let insetX = min(markerSize, bounds.width) / 2
        let insetY = min(markerSize, bounds.height) / 2
        return CGPoint(
            x: min(max(center.x, bounds.minX + insetX), bounds.maxX - insetX),
            y: min(max(center.y, bounds.minY + insetY), bounds.maxY - insetY)
        )
    }

    static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.size.width > 0 && frame.size.height > 0
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
}
