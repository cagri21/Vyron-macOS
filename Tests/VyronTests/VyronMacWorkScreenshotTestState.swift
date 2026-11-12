import VyronCore

@MainActor
final class VyronMacWorkScreenshotTestState {
    var isCurrent = true
    var failPublication = false
    var capturedImages: [VyronImageAttachment] = []
}
