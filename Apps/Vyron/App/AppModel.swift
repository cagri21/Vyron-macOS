import Combine
import Foundation
import VyronCore
import VyronModelData
import VyronModelDomain
import VyronRuntime
import VyronAutomation
import VyronDevelopment

@MainActor
final class AppModel: ObservableObject {
    // The main window and side windows share the same saved conversation list.
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: UUID? {
        didSet {
            if selectedConversationID != oldValue {
                appNavigation.trackingSelection = nil
                inspector.closeResponseChangeReview()
            }
        }
    }
    @Published var newSideChatSessions: [UUID: VyronSideChatSession] = [:]
    // Temporary side chats are window-local history and never enter the saved conversation list.
    @Published var temporarySideChatConversations: [UUID: Conversation] = [:]
    @Published var workspaceError: VyronWorkspaceError?
    @Published var statusMessage: String?
    @Published var isRunningScheduledTask = false

    var errorMessage: String? {
        get { workspaceError?.message }
        set { workspaceError = newValue.map { VyronWorkspaceError(message: $0) } }
    }

    let appNavigation = VyronAppNavigationState()
    let workspaceState: VyronWorkspaceState
    let inspector = VyronWorkspaceInspectorState()
    let sidebarState: VyronSidebarState
    let composer: VyronComposerModel
    let composerAttachments = VyronComposerAttachmentState()
    let composerSkills = VyronComposerSkillsModel()
    let foregroundRun = VyronForegroundRun()
    let followUpQuestions = VyronConversationFollowUpRequests()
    let interactions: VyronConversationInteractions
    let notifications: VyronNotificationsModel
    let handoff = VyronChatHandoffFlow()
    let computerWork = VyronComputerWorkState(
        controller: MacController(), screenshotCapture: VyronMacScreenshotCapture()
    )
    let modelSelection: VyronModelSelectionModel
    let modelDownloads: VyronModelDownloads
    let modelFeatures = VyronModelFeatureState()
    let connectionBalances: VyronConnectionBalancesModel
    let localAuthentication: VyronLocalAuthenticationModel
    let mcpConnections: MCPConnectionsModel
    let scheduledTasks: VyronScheduledTasksModel
    let voice: VyronVoiceModel

    let historyStore: VyronConversationHistoryStore
    let modelCredentialStore: ModelCredentialStore
    let modelCredentialReader: VyronModelCredentialReader
    let runtime = LocalRuntimeManager()
    let physicalMemoryBytes = Int64(clamping: ProcessInfo.processInfo.physicalMemory)
    var webAccess: any VyronWebAccessing = VyronWebClient()
    var readRenderedWebPage: (@MainActor (URL, VyronResponseIdentity, VyronWebsiteScope?) async throws -> VyronWebPage)?
    var chromeBridge = VyronChromeBridgeClient()
    var skillContextLoader: @Sendable (VyronSkillContextRequest) async throws -> VyronSkillRequestContext = {
        try await VyronSkillContextLoader.load($0)
    }

    var historyIsWritable = true
    var isShuttingDown = false
    var shutdownTasksSettled = false
    let startup = VyronAppStartup()
    var forceConversationNextSend = false
    var connectionBalanceSubscriptions: Set<AnyCancellable> = []
    private var featureObservation: AnyCancellable?

    init(
        preferences: UserDefaults,
        conversation: VyronAppConversationDependencies,
        workspace: VyronAppWorkspaceDependencies,
        models: VyronAppModelDependencies
    ) {
        workspaceState = VyronWorkspaceState(defaults: preferences)
        composer = VyronComposerModel(defaults: preferences)
        interactions = VyronConversationInteractions(defaults: preferences)
        historyStore = conversation.historyStore
        notifications = conversation.notifications
        voice = conversation.voice
        sidebarState = workspace.sidebar
        mcpConnections = workspace.mcpConnections
        scheduledTasks = workspace.scheduledTasks
        modelSelection = models.selection
        modelDownloads = models.downloads
        connectionBalances = models.balances
        modelCredentialStore = models.credentials.store
        modelCredentialReader = models.credentials.reader
        localAuthentication = models.credentials.localAuthentication

        composer.isModeCompatible = { [weak self] mode in self?.isConversationModeCompatible(mode) ?? true }
        composer.didChangeMode = { [weak self] in self?.voice.end() }

        let recoveredActivity = restoreConversationHistory()
        workspaceState.restoreWorkspaceLocation()
        loadSidebarOrganization()
        restoreSidebarProjectSelection()
        modelSelection.load()
        modelSelection.selectionChanged = { [weak self] in self?.requestModelFeatureVerification() }
        observeFeatureChanges()
        if recoveredActivity { saveHistory() }
        notificationDidSaveHistory()
        reloadNotificationReadState()
        configureNotificationObservers()
        configureConnectionBalanceObservers()
        configureScheduledTasks()
        self.voice.conversation = self
    }

    private func observeFeatureChanges() {
        // App-wide views still observe derived workflow gates across feature owners.
        let transferActivity = modelDownloads.$active.map { $0 != nil }.removeDuplicates().dropFirst().map { _ in () }
        featureObservation = Publishers.MergeMany([
            appNavigation.objectWillChange.eraseToAnyPublisher(),
            workspaceState.objectWillChange.eraseToAnyPublisher(),
            sidebarState.objectWillChange.eraseToAnyPublisher(),
            inspector.objectWillChange.eraseToAnyPublisher(),
            composer.objectWillChange.eraseToAnyPublisher(),
            composerAttachments.objectWillChange.eraseToAnyPublisher(),
            foregroundRun.objectWillChange.eraseToAnyPublisher(),
            interactions.objectWillChange.eraseToAnyPublisher(),
            notifications.objectWillChange.eraseToAnyPublisher(),
            handoff.objectWillChange.eraseToAnyPublisher(),
            computerWork.objectWillChange.eraseToAnyPublisher(),
            modelSelection.objectWillChange.eraseToAnyPublisher(),
            modelFeatures.objectWillChange.eraseToAnyPublisher(),
            transferActivity.eraseToAnyPublisher()
        ]).sink { [weak self] in self?.objectWillChange.send() }
    }
}
