import Foundation

@MainActor
protocol VyronScreenshotCapturing: AnyObject {
    func sources() async throws -> [VyronScreenshotSource]
    func capture(_ source: VyronScreenshotSource) async throws -> Data
    func requestPermission() -> Bool
    func openPermissionSettings() -> Bool
}
