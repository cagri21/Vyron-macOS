import Foundation
@testable import Vyron

@MainActor
final class VyronScreenshotPickerTestCapture: VyronScreenshotCapturing {
    private(set) var sourceRequests: [CheckedContinuation<[VyronScreenshotSource], any Error>] = []
    private(set) var captureRequests: [CheckedContinuation<Data, any Error>] = []
    private(set) var capturedSourceIDs: [String] = []
    private(set) var finishedListings = 0
    private(set) var finishedCaptures = 0
    private(set) var permissionRequests = 0
    private(set) var settingsRequests = 0
    var permissionGranted = false

    func sources() async throws -> [VyronScreenshotSource] {
        defer { finishedListings += 1 }
        return try await withCheckedThrowingContinuation { sourceRequests.append($0) }
    }

    func capture(_ source: VyronScreenshotSource) async throws -> Data {
        capturedSourceIDs.append(source.id)
        defer { finishedCaptures += 1 }
        return try await withCheckedThrowingContinuation { captureRequests.append($0) }
    }

    func requestPermission() -> Bool {
        permissionRequests += 1
        return permissionGranted
    }

    func openPermissionSettings() -> Bool {
        settingsRequests += 1
        return true
    }
}
