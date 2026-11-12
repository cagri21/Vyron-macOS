import VyronAutomation

@MainActor
protocol VyronComputerPreviewCapturing: AnyObject {
    func capturePreview(application: DesktopApplication) async throws -> VyronMacControlPreview
}
