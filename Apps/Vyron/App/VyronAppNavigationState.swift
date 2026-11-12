import Combine
import Foundation

@MainActor
final class VyronAppNavigationState: ObservableObject {
    @Published var destination = VyronAppDestination.workspace
    @Published var settingsSection = VyronSettingsSection.general
    @Published var showSetup = false
    @Published var showScheduledTasks = false
    @Published var showAutomation = false
    @Published var showWorkspace = false {
        didSet {
            if showWorkspace { trackingSelection = nil }
        }
    }
    @Published var trackingSelection: VyronTrackingSelection?
}
