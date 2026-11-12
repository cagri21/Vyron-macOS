import Combine

@MainActor
final class VyronComputerWorkState: ObservableObject {
    @Published var isPlanningControls = false
    @Published var automaticRequestRouting = true
    @Published var pendingAgentGoal: PendingAgentGoal?
    @Published var isComputerWorkActive = false

    var agentConversation: PendingAgentGoal?
    var stopAutomation: (@MainActor () -> Void)?
    let macWorkOverlay = VyronComputerActionOverlay()
    var macWorkController: any VyronMacWorkControlling
    var macWorkScreenshotCapture: any VyronScreenshotCapturing

    var isIdle: Bool { !isPlanningControls && !isComputerWorkActive && pendingAgentGoal == nil }

    init(controller: any VyronMacWorkControlling, screenshotCapture: any VyronScreenshotCapturing) {
        macWorkController = controller
        macWorkScreenshotCapture = screenshotCapture
    }
}
