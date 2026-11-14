import Foundation
import VyronAutomation
import XCTest
@testable import Vyron

@MainActor
final class VyronMacWorkIntegrationController: VyronMacWorkControlling {
    let permissions = MacPermissionState(accessibilityGranted: true, screenCaptureGranted: true)

    func requestAccessibility() { XCTFail("This fixture already has Accessibility permission.") }

    func availableApplications() -> [DesktopApplication] { applications() }

    func applications() -> [DesktopApplication] {
        [DesktopApplication(
            id: VyronMacWorkIntegrationProvider.applicationID,
            name: "Preview app", bundleIdentifier: VyronMacWorkIntegrationProvider.applicationID,
            processIdentifier: 42
        )]
    }

    func launch(applicationID: String) async throws -> DesktopApplication {
        throw MacControlError.applicationUnavailable
    }
    func attachedApplication(at url: URL) -> DesktopApplication? { nil }
    func launch(attachedApplicationAt url: URL, expectedApplicationID: String) async throws -> DesktopApplication {
        throw MacControlError.applicationUnavailable
    }
    func activate(application: DesktopApplication) throws { throw MacControlError.applicationUnavailable }
    func inspect(application: DesktopApplication) throws -> AutomationSnapshot {
        throw MacControlError.applicationUnavailable
    }
    func elementInfo(elementID: Int, snapshotID: UUID) throws -> NativeElementInfo {
        throw MacControlError.applicationUnavailable
    }
    func click(elementID: Int, snapshotID: UUID) throws { throw MacControlError.applicationUnavailable }
    func typeText(_ text: String, elementID: Int, snapshotID: UUID) throws {
        throw MacControlError.applicationUnavailable
    }
    func pressKey(_ key: String, application: DesktopApplication) throws {
        throw MacControlError.applicationUnavailable
    }
    func openProject(_ url: URL) async throws -> DesktopApplication { throw MacControlError.applicationUnavailable }
}
