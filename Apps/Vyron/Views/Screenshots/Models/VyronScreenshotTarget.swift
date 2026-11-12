enum VyronScreenshotTarget: Equatable, Sendable {
    case window(VyronScreenshotWindowTarget)
    case display(VyronScreenshotDisplayTarget)
}
