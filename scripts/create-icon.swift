import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let unit = CGFloat(pixels) / 1024
        let transform = AffineTransform(scale: unit)
        (transform as NSAffineTransform).concat()

        let shape = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 205, yRadius: 205)
        let gradient = NSGradient(
            starting: NSColor(srgbRed: 42.0 / 255, green: 42.0 / 255, blue: 42.0 / 255, alpha: 1),
            ending: NSColor(srgbRed: 24.0 / 255, green: 24.0 / 255, blue: 24.0 / 255, alpha: 1)
        )!
        gradient.draw(in: shape, angle: -70)
        NSColor.white.withAlphaComponent(0.10).setStroke()
        shape.lineWidth = 3
        shape.stroke()

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 300, y: 670))
        mark.line(to: NSPoint(x: 500, y: 330))
        mark.line(to: NSPoint(x: 700, y: 670))
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.lineWidth = 82
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setStroke()
        mark.stroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: 730, y: 690, width: 60, height: 60))
        NSColor(srgbRed: 0.72, green: 0.72, blue: 0.72, alpha: 1).setFill()
        dot.fill()

        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
