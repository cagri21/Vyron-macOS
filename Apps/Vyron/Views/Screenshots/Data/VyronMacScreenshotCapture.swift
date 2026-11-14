import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import VyronAutomation

@MainActor
final class VyronMacScreenshotCapture: VyronScreenshotCapturing {
    private static let maximumDimension: CGFloat = 2_048
    private static let minimumWindowDimension: CGFloat = 100

    func sources() async throws -> [VyronScreenshotSource] {
        let content = try await shareableContent()
        let windows = content.windows.compactMap(windowSource)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let displays = content.displays.sorted { $0.displayID < $1.displayID }
            .enumerated().map { index, display in
                VyronScreenshotSource(
                    id: "display-\(display.displayID)",
                    name: VyronScreenshotText.displayName(index + 1),
                    target: .display(VyronScreenshotDisplayTarget(displayID: display.displayID))
                )
            }
        return windows + displays
    }

    func capture(_ source: VyronScreenshotSource) async throws -> Data {
        let content = try await shareableContent()
        let filter: SCContentFilter
        switch source.target {
        case .window(let target):
            guard let window = content.windows.first(where: {
                $0.windowID == target.windowID
                    && $0.owningApplication?.processID == target.processID
                    && $0.owningApplication?.bundleIdentifier == target.bundleIdentifier
                    && windowSource($0) != nil
            }) else { throw VyronScreenshotCaptureError.sourceUnavailable }
            filter = SCContentFilter(desktopIndependentWindow: window)
        case .display(let target):
            guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
                throw VyronScreenshotCaptureError.sourceUnavailable
            }
            let ownApplications = content.applications.filter {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }
            filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            if #available(macOS 14.2, *) {
                filter.includeMenuBar = true
            }
        }
        let configuration = try captureConfiguration(for: filter)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw VyronScreenshotCaptureError.permissionRequired }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw VyronScreenshotCaptureError.encodingFailed
        }
        return data
    }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openPermissionSettings() -> Bool {
        VyronMacPrivacyPane.screenRecording.openSettings()
    }

    private func shareableContent() async throws -> SCShareableContent {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw VyronScreenshotCaptureError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw VyronScreenshotCaptureError.permissionRequired }
        return content
    }

    private func windowSource(_ window: SCWindow) -> VyronScreenshotSource? {
        guard window.isOnScreen, window.windowLayer == 0,
            window.frame.width >= Self.minimumWindowDimension,
            window.frame.height >= Self.minimumWindowDimension,
            let application = window.owningApplication,
            application.processID != ProcessInfo.processInfo.processIdentifier,
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        let name = application.applicationName == title ? title : "\(application.applicationName) — \(title)"
        return VyronScreenshotSource(
            id: "window-\(application.processID)-\(window.windowID)",
            name: name,
            target: .window(VyronScreenshotWindowTarget(
                windowID: window.windowID,
                processID: application.processID,
                bundleIdentifier: application.bundleIdentifier
            ))
        )
    }

    private func captureConfiguration(for filter: SCContentFilter) throws -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let nativeWidth = filter.contentRect.width * CGFloat(filter.pointPixelScale)
        let nativeHeight = filter.contentRect.height * CGFloat(filter.pointPixelScale)
        guard nativeWidth.isFinite, nativeHeight.isFinite, nativeWidth > 0, nativeHeight > 0 else {
            throw VyronScreenshotCaptureError.sourceUnavailable
        }
        let scale = min(1, Self.maximumDimension / max(nativeWidth, nativeHeight))
        configuration.width = max(1, Int(nativeWidth * scale))
        configuration.height = max(1, Int(nativeHeight * scale))
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }
}
