import CoreGraphics

struct VyronScreenshotWindowTarget: Equatable, Sendable {
    let windowID: CGWindowID
    let processID: Int32
    let bundleIdentifier: String
}
