enum VyronScreenshotCaptureError: Error, Sendable {
    case permissionRequired
    case sourceUnavailable
    case encodingFailed
}
