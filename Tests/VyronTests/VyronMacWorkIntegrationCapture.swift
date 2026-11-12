import Foundation
@testable import Vyron

@MainActor
final class VyronMacWorkIntegrationCapture: VyronScreenshotCapturing {
    private let data: Data
    private var pendingCaptures: [CheckedContinuation<Data, Never>] = []
    private(set) var sourceRequests = 0
    private(set) var captureRequests = 0
    private(set) var finishedCaptures = 0
    private(set) var permissionRequests = 0
    var holdsCapture = false

    init(data: Data) {
        self.data = data
    }

    func sources() async throws -> [VyronScreenshotSource] {
        sourceRequests += 1
        return [VyronScreenshotSource(
            id: VyronMacWorkIntegrationProvider.sourceID, name: "Preview app window",
            target: .window(VyronScreenshotWindowTarget(
                windowID: 17, processID: 42,
                bundleIdentifier: VyronMacWorkIntegrationProvider.applicationID
            ))
        )]
    }

    func capture(_ source: VyronScreenshotSource) async throws -> Data {
        captureRequests += 1
        defer { finishedCaptures += 1 }
        if holdsCapture {
            // Deliberately completes after cancellation to exercise response ownership guards.
            return await withCheckedContinuation { pendingCaptures.append($0) }
        }
        return data
    }

    func releaseCaptures() {
        holdsCapture = false
        let continuations = pendingCaptures
        pendingCaptures.removeAll()
        for continuation in continuations { continuation.resume(returning: data) }
    }

    func requestPermission() -> Bool {
        permissionRequests += 1
        return true
    }

    func openPermissionSettings() -> Bool { false }
}
