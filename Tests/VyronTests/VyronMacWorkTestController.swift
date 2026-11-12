import Foundation
import VyronAutomation
@testable import Vyron

@MainActor
final class VyronMacWorkTestController: VyronMacWorkControlling {
    static var app: DesktopApplication {
        DesktopApplication(
            id: "com.apple.calculator", name: "Calculator",
            bundleIdentifier: "com.apple.calculator", processIdentifier: 42
        )
    }

    var permissions = MacPermissionState(accessibilityGranted: true, screenCaptureGranted: true)
    var catalog = [app]
    var running = [app]
    var elementTitle = "+"
    var elementRole = "AXButton"
    var elementIsSecure = false
    var targetFrame: CGRect?
    var snapshotDate: Date?
    var inspectionText = "[1] Button · + {click}"
    var onLaunch: (@MainActor () async throws -> Void)?
    var onActivate: (@MainActor () -> Void)?
    var onElementAction: (@MainActor () throws -> Void)?
    var launchedIDs: [String] = []
    var clickedIDs: [Int] = []
    var typedTexts: [String] = []
    var keys: [String] = []
    var openedProjects: [URL] = []
    var accessibilityRequests = 0
    var inspections = 0

    func requestAccessibility() { accessibilityRequests += 1 }
    func availableApplications() -> [DesktopApplication] { catalog }
    func applications() -> [DesktopApplication] { running }

    func launch(applicationID: String) async throws -> DesktopApplication {
        launchedIDs.append(applicationID)
        try await onLaunch?()
        guard let installed = catalog.first(where: { $0.id == applicationID }) else {
            throw MacControlError.applicationUnavailable
        }
        let app = DesktopApplication(
            id: installed.id, name: installed.name, bundleIdentifier: installed.bundleIdentifier, processIdentifier: 42
        )
        running = [app]
        catalog = [app]
        return app
    }

    func activate(application: DesktopApplication) throws { onActivate?() }

    func inspect(application: DesktopApplication) throws -> AutomationSnapshot {
        guard permissions.accessibilityGranted else { throw MacControlError.accessibilityRequired }
        inspections += 1
        return AutomationSnapshot(
            applicationName: application.name, applicationID: application.id,
            capturedAt: snapshotDate ?? Date(), text: inspectionText
        )
    }

    func elementInfo(elementID: Int, snapshotID: UUID) throws -> NativeElementInfo {
        guard let app = running.first else { throw MacControlError.applicationUnavailable }
        return NativeElementInfo(
            elementID: elementID, applicationID: app.id, role: elementRole,
            title: elementTitle, description: "", value: "", actions: ["click", "typeText"], isSecure: elementIsSecure
        )
    }

    func elementFrame(elementID: Int, snapshotID: UUID) throws -> CGRect? { targetFrame }

    func click(elementID: Int, snapshotID: UUID) throws {
        try onElementAction?()
        clickedIDs.append(elementID)
    }

    func typeText(_ text: String, elementID: Int, snapshotID: UUID) throws {
        try onElementAction?()
        typedTexts.append(text)
    }

    func pressKey(_ key: String, application: DesktopApplication) throws { keys.append(key) }

    func openProject(_ url: URL) async throws -> DesktopApplication {
        openedProjects.append(url)
        guard let xcode = catalog.first(where: { $0.id == "com.apple.dt.Xcode" }) else {
            throw MacControlError.applicationUnavailable
        }
        return xcode
    }
}
