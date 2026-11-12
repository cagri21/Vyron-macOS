import Foundation
import VyronAutomation

@MainActor
protocol VyronMacWorkControlling {
    var permissions: MacPermissionState { get }
    func requestAccessibility()
    func availableApplications() -> [DesktopApplication]
    func applications() -> [DesktopApplication]
    func launch(applicationID: String) async throws -> DesktopApplication
    func activate(application: DesktopApplication) throws
    func inspect(application: DesktopApplication) throws -> AutomationSnapshot
    func elementInfo(elementID: Int, snapshotID: UUID) throws -> NativeElementInfo
    func elementFrame(elementID: Int, snapshotID: UUID) throws -> CGRect?
    func click(elementID: Int, snapshotID: UUID) throws
    func typeText(_ text: String, elementID: Int, snapshotID: UUID) throws
    func pressKey(_ key: String, application: DesktopApplication) throws
    func openProject(_ url: URL) async throws -> DesktopApplication
}

extension VyronMacWorkControlling {
    func elementFrame(elementID: Int, snapshotID: UUID) throws -> CGRect? { nil }
}
