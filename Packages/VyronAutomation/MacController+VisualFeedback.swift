import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

extension MacController {
    /// Captures only the selected app's visible window after a separate, explicit permission grant.
    /// Callers keep this in memory for the local activity preview; it is not model input.
    public func capturePreview(application: DesktopApplication) async throws -> VyronMacControlPreview {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw VyronMacPreviewError.permissionRequired }
        let running = try previewApplication(application)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        _ = try previewApplication(application)
        let windows = content.windows.filter {
            $0.owningApplication?.processID == running.processIdentifier
                && $0.windowLayer == 0 && $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0
        }
        let focusedFrame = focusedPreviewWindowFrame(processID: running.processIdentifier)
        let window = focusedFrame.flatMap { frame in
            windows.first {
                abs($0.frame.minX - frame.minX) < 2 && abs($0.frame.minY - frame.minY) < 2
                    && abs($0.frame.width - frame.width) < 2 && abs($0.frame.height - frame.height) < 2
            }
        } ?? windows.first
        guard let window else { throw VyronMacPreviewError.windowUnavailable }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let maximumDimension: CGFloat = 960
        let scale = min(1, maximumDimension / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = true
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        _ = try previewApplication(application)
        guard CGPreflightScreenCaptureAccess() else { throw VyronMacPreviewError.permissionRequired }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let imageData = representation.representation(using: .png, properties: [:]) else {
            throw VyronMacPreviewError.encodingFailed
        }
        return VyronMacControlPreview(
            applicationID: application.id,
            capturedAt: Date(),
            screenFrame: window.frame,
            imageData: imageData
        )
    }

    /// AX geometry uses the same top-left screen coordinate space as ScreenCaptureKit windows.
    func visualFrame(of element: AXUIElement) -> CGRect? {
        guard let position = previewAttribute(element, kAXPositionAttribute),
            let size = previewAttribute(element, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        let positionValue = unsafeDowncast(position, to: AXValue.self)
        let sizeValue = unsafeDowncast(size, to: AXValue.self)
        guard AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &dimensions),
            [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
            dimensions.width > 0, dimensions.height > 0
        else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func previewApplication(_ application: DesktopApplication) throws -> NSRunningApplication {
        guard application.processIdentifier > 0,
            let running = NSRunningApplication(processIdentifier: application.processIdentifier),
            !running.isTerminated,
            running.bundleIdentifier == application.bundleIdentifier
        else { throw VyronMacPreviewError.applicationUnavailable }
        return running
    }

    private func focusedPreviewWindowFrame(processID: Int32) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let value = previewAttribute(app, kAXFocusedWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return visualFrame(of: unsafeDowncast(value, to: AXUIElement.self))
    }

    private func previewAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
