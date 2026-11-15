import Combine
import Foundation
import VyronAutomation
import VyronCore
import VyronModelDomain

private struct AgentPolicyError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

struct MonitorEvent: Identifiable {
    let id = UUID()
    let date: Date
    let summary: String
}

enum ReviewedMacAction {
    case launch(DesktopApplication)
    case activate(DesktopApplication)
    case openURL(URL, DesktopApplication?)
    case click(DesktopApplication, UUID, Int)
    case type(DesktopApplication, UUID, Int, String)
    case key(DesktopApplication, String)
    case inspect(DesktopApplication)
}

struct MacActionReview: Identifiable {
    let id = UUID()
    let details: String
    let action: ReviewedMacAction
    let requiredSnapshotID: UUID?
    let taskRunID: UUID?
    let stepSummary: String
    let isAgentAction: Bool
}

struct FollowTaskEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let summary: String
}

@MainActor
final class AutomationModel: ObservableObject {
    @Published var applications: [DesktopApplication] = []
    @Published var selectedApplicationID: String? {
        didSet {
            if oldValue != selectedApplicationID && !isRoutingApplication {
                stopTask(reason: VyronControlText.selectedAppChanged)
                stopMonitoring()
                cancelPlanning()
                cancelExecution()
                snapshot = nil
                proposal = nil
                events = []
                status = nil
                pendingAction = nil
                showConfirmation = false
            }
            if oldValue != selectedApplicationID { restartControlPreview() }
        }
    }
    @Published var selectedBrowserID = VyronAutomationBrowserSelection.systemDefault.rawValue
    @Published var accessibilityGranted = false
    @Published var screenCaptureGranted = false
    @Published var snapshot: AutomationSnapshot?
    @Published var error: String?
    @Published var status: String?
    @Published var elementID = ""
    @Published var textToType = ""
    @Published var browserURL = ""
    @Published var selectedKey = VyronAutomationManualKey.returnKey.rawValue
    @Published var isExecuting = false
    @Published var isMonitoring = false
    @Published var monitorInterval = VyronAutomationMonitorInterval.standard.rawValue {
        didSet { if isMonitoring { startMonitoring() } }
    }
    @Published var events: [MonitorEvent] = []
    @Published var pendingAction: MacActionReview?
    @Published var showConfirmation = false
    @Published var plannerInstruction = ""
    @Published var proposal: ControlProposal?
    @Published var isPlanning = false
    @Published var systemStatus: SystemStatus?
    @Published var plannerMode = VyronAutomationPlannerMode.agent.rawValue
    @Published var isFollowingTask = false
    @Published var taskState = ""
    @Published var taskEvents: [FollowTaskEvent] = []
    @Published var approvedTaskActions = 0
    @Published var taskPlanningPasses = 0
    @Published var automaticAppChoice = true
    @Published var routineAutonomy = true
    @Published var agentEffort: AgentEffort = .automatic
    @Published var agentDecision: AgentDecision?
    @Published var nextAgentWake: Date?
    @Published var agentMaximumSteps = 16
    @Published var controlPreview: VyronMacControlPreview?
    @Published var controlPreviewMessage: String?
    @Published var controlFeedback: VyronComputerActionFeedback?
    var controlPreviewTask: Task<Void, Never>?
    var controlPreviewGeneration: UUID?
    let controlOverlay = VyronComputerActionOverlay()

    let controller: MacController
    let previewCapture: any VyronComputerPreviewCapturing
    private weak var chat: AppModel?
    private var monitorTask: Task<Void, Never>?
    private var planningTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var executionID: UUID?
    private var planningID: UUID?
    private var previousMonitorText: String?
    private var monitorID: UUID?
    private var proposalSnapshotID: UUID?
    private var isReviewingProposal = false
    private let systemMonitor = SystemMonitor()
    private var performanceTask: Task<Void, Never>?
    private var taskRunID: UUID?
    private var taskApplication: DesktopApplication?
    private var taskGoal = ""
    private var verificationTask: Task<Void, Never>?
    private var isRoutingApplication = false
    private var approvedOrigins: Set<String> = []
    private var agentFailureCount = 0
    private var agentPlanningRecoveries = 0
    private var chatRequestID: UUID?

    init(previewCapture: (any VyronComputerPreviewCapturing)? = nil) {
        let controller = MacController()
        self.controller = controller
        self.previewCapture = previewCapture ?? controller
    }

    var selectedApplication: DesktopApplication? { applications.first { $0.id == selectedApplicationID } }
    var isAgentMode: Bool { plannerMode == VyronAutomationPlannerMode.agent.rawValue }
    var permissionLocation: String { MacController.permissionSettingsPath }
    var browsers: [DesktopApplication] {
        controller.browsers()
    }
    var snapshotIsFresh: Bool {
        guard let snapshot, snapshot.applicationID == selectedApplicationID else { return false }
        let age = Date().timeIntervalSince(snapshot.capturedAt)
        return age >= 0 && age < TimeInterval(VyronAutomationSnapshotLimits.freshnessSeconds)
    }
    var availableElementIDs: Set<Int> {
        guard let text = snapshot?.text,
            let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#)
        else { return [] }
        let nsText = text as NSString
        return Set(
            regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap {
                Int(nsText.substring(with: $0.range(at: 1)))
            }
        )
    }

    func configure(chat: AppModel) {
        self.chat = chat
        chat.computerWork.stopAutomation = { [weak self] in self?.close() }
        refresh()
        startPerformanceMonitoring()
        if let request = chat.computerWork.pendingAgentGoal { acceptPendingGoal(request) }
    }

    func acceptPendingGoal(_ request: PendingAgentGoal) {
        guard let chat, chat.canStartAgentGoal(request.id), chatRequestID != request.id else { return }
        chatRequestID = request.id
        plannerMode = VyronAutomationPlannerMode.agent.rawValue
        plannerInstruction = request.goal
        agentEffort = request.effort
        if !accessibilityGranted {
            taskState = VyronControlText.waitingPermission
            status = VyronControlText.allowAndStart(permissionLocation)
            chat.reportAgentProgress(
                requestID: request.id,
                state: taskState + " " + (status ?? ""),
                trace: [],
                finished: false
            )
        } else if chat.modelDownloads.isActive {
            taskState = VyronControlText.waitingDownload
            chat.reportAgentProgress(requestID: request.id, state: taskState, trace: [], finished: false)
        } else {
            startAgent()
        }
    }

    func refresh() {
        let permissions = controller.permissions
        accessibilityGranted = permissions.accessibilityGranted
        screenCaptureGranted = permissions.screenCaptureGranted
        applications = isAgentMode ? controller.availableApplications() : controller.applications()
        if !applications.contains(where: { $0.id == selectedApplicationID }) {
            selectedApplicationID = applications.first?.id
        }
        if !accessibilityGranted {
            stopMonitoring()
            stopTask(reason: VyronControlText.accessibilityUnavailable, activityState: .failed)
            clearInspection()
        }
        restartControlPreview()
    }

    func requestAccessibility() {
        controller.requestAccessibility()
        refresh()
        status = VyronControlText.allowAndRefresh(permissionLocation)
    }

    func requestScreenCapture() {
        _ = controller.requestScreenCapture()
        refresh()
    }

    func openPrivacySettings() { controller.openPrivacySettings() }

    func inspect() {
        guard let application = selectedApplication else { return }
        do {
            snapshot = try controller.inspect(application: application)
            error = nil
            proposal = nil
            status = VyronControlText.snapshotLocal
        } catch {
            self.error = error.localizedDescription
            clearInspection()
            stopMonitoring()
            refresh()
        }
    }

    func reviewActivate() {
        guard let app = selectedApplication else { return }
        review(.activate(app), details: VyronControlText.activateReview(app.name))
    }

    func reviewClick() {
        guard let app = selectedApplication, let snapshot else { return }
        guard requireFreshSnapshot(), let id = validElementID() else { return }
        review(
            .click(app, snapshot.id, id),
            details: VyronControlText.clickReview(app.name, id, elementDescription(id))
        )
    }

    func reviewType() {
        guard let app = selectedApplication, let snapshot else { return }
        guard requireFreshSnapshot(), let id = validElementID() else { return }
        guard !textToType.isEmpty, textToType.utf8.count <= 8_000 else {
            error = VyronControlText.typeLimit
            return
        }
        review(
            .type(app, snapshot.id, id, textToType),
            details:
                VyronControlText.typeReview(app.name, id, elementDescription(id), textToType)
        )
    }

    func reviewKey(_ key: String) {
        guard let app = selectedApplication else { return }
        review(
            .key(app, key),
            details: VyronControlText.keyReview(app.name, key.capitalized)
        )
    }

    func reviewURL() {
        let entered = browserURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = entered.contains("://") ? entered : "https://" + entered
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil, url.user == nil, url.password == nil
        else {
            error = VyronControlText.validWebsite
            return
        }
        let browser = browsers.first { $0.id == selectedBrowserID }
        review(
            .openURL(url, browser),
            details: VyronControlText.openURLReview(
                url.absoluteString, browser?.name ?? VyronControlText.defaultBrowser
            )
        )
    }

    private func review(_ action: ReviewedMacAction, details: String) {
        guard !isFollowingTask || isReviewingProposal else {
            error = VyronControlText.stopBeforeManual
            return
        }
        pendingAction = MacActionReview(
            details: details,
            action: action,
            requiredSnapshotID: isReviewingProposal ? proposalSnapshotID : nil,
            taskRunID: isReviewingProposal && isFollowingTask ? taskRunID : nil,
            stepSummary: isReviewingProposal
                ? (proposal.map { "\($0.kind.rawValue): " + String($0.explanation.prefix(220)) }
                    ?? String(details.prefix(220)))
                : String(details.prefix(220)),
            isAgentAction: isFollowingTask && isAgentMode
        )
        showConfirmation = true
    }

    func executePending(automatic: Bool = false) {
        guard let action = pendingAction, !isExecuting else { return }
        if let taskID = action.taskRunID, taskID != taskRunID || !isFollowingTask { return }
        if action.isAgentAction {
            do {
                switch try policy(for: action) {
                case .refused(let reason):
                    error = reason
                    stopTask(reason: VyronControlText.actionNotPermitted, activityState: .failed)
                    return
                case .review(let reason) where automatic:
                    status = VyronControlText.reviewNeeded(reason)
                    taskState = VyronControlText.reviewBeforeContinue
                    showConfirmation = false
                    return
                default: break
                }
            } catch {
                self.error = error.localizedDescription
                stopTask(reason: VyronControlText.targetNotVerified, activityState: .failed)
                return
            }
        }
        if let requiredSnapshotID = action.requiredSnapshotID {
            guard requireFreshSnapshot(), snapshot?.id == requiredSnapshotID else {
                error = VyronControlText.proposalExpired
                pendingAction = nil
                if action.taskRunID != nil {
                    stopTask(
                        reason:
                            VyronControlText.taskActionExpired,
                        activityState: .failed
                    )
                }
                return
            }
        }
        pendingAction = nil
        isExecuting = true
        stopMonitoring()
        let id = UUID()
        executionID = id
        let previousState = snapshot?.text ?? ""
        executionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if executionID == id {
                    isExecuting = false
                    executionID = nil
                    executionTask = nil
                }
            }
            do {
                let sendAction: @MainActor @Sendable () async throws -> CGRect? = { [self] in
                    try await sendReviewedAction(action, executionID: id, automatic: automatic)
                }
                let preservesSnapshot: Bool
                if case .inspect = action.action {
                    preservesSnapshot = true
                } else {
                    preservesSnapshot = false
                }
                let controlTargetFrame = if !preservesSnapshot, let actions = chat?.computerWork.macActions {
                    try await actions.perform(sendAction)
                } else {
                    try await sendAction()
                }
                try Task.checkCancellation()
                guard executionID == id else { return }
                recordSuccessfulControlAction(action.action, targetFrame: controlTargetFrame)
                error = nil
                status =
                    preservesSnapshot
                    ? VyronControlText.freshSnapshot
                    : VyronControlText.actionSent
                proposal = nil
                if !preservesSnapshot { snapshot = nil }
                if let taskID = action.taskRunID, taskRunID == taskID {
                    approvedTaskActions += 1
                    recordTask(
                        "\(automatic ? "Automatic" : "Approved") action \(approvedTaskActions) was sent: \(action.stepSummary). Checking the actual app state next."
                    )
                    taskState = VyronControlText.checkingAction(approvedTaskActions)
                    observeTaskResult(taskID: taskID, before: previousState, actionSummary: action.stepSummary)
                }
            } catch {
                if !Task.isCancelled, executionID == id {
                    self.error = error.localizedDescription
                    if action.isAgentAction {
                        agentFailureCount += 1
                        recordTask(
                            "Native action failed: \(String(error.localizedDescription.prefix(400))). Verify the app state before retrying any side effect."
                        )
                    }
                    if action.taskRunID != nil {
                        stopTask(reason: VyronControlText.actionFailedStop, activityState: .failed)
                    }
                }
            }
        }
    }

    private func sendReviewedAction(
        _ review: MacActionReview, executionID id: UUID, automatic: Bool
    ) async throws -> CGRect? {
        try Task.checkCancellation()
        guard executionID == id, review.taskRunID.map({ isFollowingTask && taskRunID == $0 }) ?? true else {
            throw CancellationError()
        }
        if let snapshotID = review.requiredSnapshotID {
            guard requireFreshSnapshot(), snapshot?.id == snapshotID else { throw MacControlError.snapshotExpired }
        }
        try validatePolicyBeforeMutation(review, automatic: automatic)

        switch review.action {
        case .launch(let app):
            let running = try await controller.launch(application: app)
            try Task.checkCancellation()
            guard executionID == id else { throw CancellationError() }
            routeAgent(to: running)
        case .openURL(let url, let browser):
            try await controller.openBrowserAndWait(url: url, browser: browser)
            guard executionID == id else { throw CancellationError() }
            if !automatic, let origin = AutomationPolicy.origin(for: url) { approvedOrigins.insert(origin) }
        case .activate(let app):
            try controller.activate(application: app)
        case .inspect(let app):
            snapshot = try controller.inspect(application: app)
        case .key(let app, let key):
            try await focusForInput(to: app, executionID: id, snapshotID: review.requiredSnapshotID)
            if let snapshotID = review.requiredSnapshotID {
                guard let expected = snapshot, expected.id == snapshotID,
                    try controller.inspect(application: app).text == expected.text
                else { throw MacControlError.snapshotExpired }
                try validateQueuedAction(id, application: app, snapshotID: snapshotID)
            }
            try validatePolicyBeforeMutation(review, automatic: automatic)
            try controller.pressKey(key, application: app)
        case .click(let app, let snapshotID, let elementID):
            try await focusForInput(to: app, executionID: id, snapshotID: snapshotID)
            try validatePolicyBeforeMutation(review, automatic: automatic)
            let frame = try controller.elementFrame(elementID: elementID, snapshotID: snapshotID)
            try controller.click(elementID: elementID, snapshotID: snapshotID)
            return frame
        case .type(let app, let snapshotID, let elementID, let text):
            try await focusForInput(to: app, executionID: id, snapshotID: snapshotID)
            try validatePolicyBeforeMutation(review, automatic: automatic)
            let frame = try controller.elementFrame(elementID: elementID, snapshotID: snapshotID)
            try controller.typeText(text, elementID: elementID, snapshotID: snapshotID)
            return frame
        }
        return nil
    }

    private func focusForInput(to app: DesktopApplication, executionID: UUID, snapshotID: UUID?) async throws {
        try validateQueuedAction(executionID, application: app, snapshotID: snapshotID)
        try controller.activate(application: app)
        try await Task.sleep(for: VyronAutomationActionTiming.activationSettleDelay)
        try validateQueuedAction(executionID, application: app, snapshotID: snapshotID)
    }

    private func validateQueuedAction(_ id: UUID, application: DesktopApplication, snapshotID: UUID?) throws {
        try Task.checkCancellation()
        guard executionID == id, selectedApplicationID == application.id else { throw CancellationError() }
        if let snapshotID {
            guard requireFreshSnapshot(), snapshot?.id == snapshotID else { throw MacControlError.snapshotExpired }
        }
    }

    private func cancelExecution() {
        executionID = nil
        executionTask?.cancel()
        executionTask = nil
        isExecuting = false
        clearControlFeedback()
    }

    func cancelReview() { pendingAction = nil }

    func startMonitoring() {
        stopMonitoring()
        guard !isFollowingTask else {
            error = VyronControlText.stopBeforeMonitor
            return
        }
        guard accessibilityGranted, let app = selectedApplication else {
            error = VyronControlText.monitorPermission
            return
        }
        isMonitoring = true
        previousMonitorText = nil
        let id = UUID()
        monitorID = id
        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, monitorID == id, selectedApplicationID == app.id {
                do {
                    let current = try controller.inspect(application: app)
                    let normalized = Self.normalized(current.text)
                    if let previousMonitorText, previousMonitorText != normalized {
                        let summary = Self.changeSummary(before: previousMonitorText, after: normalized)
                        events.insert(MonitorEvent(date: current.capturedAt, summary: summary), at: 0)
                        if events.count > 30 { events.removeLast(events.count - 30) }
                    } else if previousMonitorText == nil {
                        events.insert(
                            MonitorEvent(
                                date: current.capturedAt,
                                summary: VyronControlText.monitorStarted(app.name)
                            ),
                            at: 0
                        )
                        if events.count > 30 { events.removeLast(events.count - 30) }
                    }
                    previousMonitorText = normalized
                    snapshot = current
                    try await Task.sleep(for: .seconds(monitorInterval))
                } catch {
                    if !Task.isCancelled, monitorID == id {
                        self.error = VyronControlText.monitorStopped(error.localizedDescription)
                        clearInspection()
                        stopMonitoring()
                        refresh()
                    }
                    return
                }
            }
        }
    }

    func stopMonitoring() {
        monitorID = nil
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        previousMonitorText = nil
    }

    func plan() {
        guard requireBuiltinModelForComputerTools() else { return }
        guard let chat, !isFollowingTask, !isPlanning, !chat.foregroundRun.isGenerating, !chat.modelDownloads.isActive,
            chat.modelSelection.isConnected, chat.modelSelection.modelIsAvailable, let app = selectedApplication,
            let snapshot, requireFreshSnapshot()
        else { return }
        let instruction = plannerInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, instruction.count <= VyronTaskPromptLimits.maximumCharacters else {
            error = VyronControlText.actionDescriptionLimit(VyronTaskPromptLimits.localizedMaximumCharacters)
            return
        }
        stopMonitoring()
        let id = UUID()
        planningID = id
        isPlanning = true
        chat.computerWork.isPlanningControls = true
        proposal = nil
        error = nil
        planningTask = Task { @MainActor [weak self, weak chat] in
            guard let self, let chat else { return }
            defer {
                if planningID == id {
                    planningID = nil
                    isPlanning = false
                    chat.computerWork.isPlanningControls = false
                    planningTask = nil
                }
            }
            do {
                let result = try await chat.modelSelection.builtinClient.proposeControl(
                    model: chat.modelSelection.selectedModel,
                    instruction: instruction,
                    snapshot: snapshot.text,
                    applicationID: app.id
                )
                guard planningID == id, selectedApplicationID == app.id else { return }
                if result.kind == .complete, !snapshotIsFresh || self.snapshot?.id != snapshot.id {
                    error =
                        VyronControlText.completionOldSnapshot
                    proposal = nil
                    return
                }
                proposal = try result.validated(
                    expectedApplicationID: app.id,
                    availableElementIDs: availableElementIDs
                )
                proposalSnapshotID = snapshot.id
                status =
                    result.kind == .complete
                    ? VyronControlText.completeVerifyCurrent
                    : VyronControlText.proposalOnly
            } catch {
                if !Task.isCancelled, planningID == id { self.error = error.localizedDescription }
            }
        }
    }

    func cancelPlanning() {
        if isFollowingTask {
            stopTask(reason: VyronControlText.stoppedByUser)
            return
        }
        cancelPlanningRequest()
    }

    private func cancelPlanningRequest() {
        planningID = nil
        planningTask?.cancel()
        planningTask = nil
        isPlanning = false
        chat?.computerWork.isPlanningControls = false
    }

    func reviewProposal() {
        guard let proposal, let app = selectedApplication else { return }
        if isFollowingTask && isAgentMode, let runID = taskRunID {
            do {
                pendingAction = try agentAction(proposal, application: app, runID: runID)
                showConfirmation = true
            } catch {
                self.error = error.localizedDescription
                agentFailureCount += 1
                recordTask(
                    VyronControlText.reviewTargetFailed(String(error.localizedDescription.prefix(400)))
                )
                stopTask(
                    reason:
                        VyronControlText.actionNotVerified,
                    activityState: .failed
                )
            }
            return
        }
        guard requireFreshSnapshot(), snapshot?.id == proposalSnapshotID else {
            error = VyronControlText.proposalOldSnapshot
            return
        }
        isReviewingProposal = true
        defer { isReviewingProposal = false }
        do {
            let validated = try proposal.validated(
                expectedApplicationID: app.id,
                availableElementIDs: availableElementIDs
            )
            let reason = VyronControlText.reviewTarget(validated.explanation, app.name)
            switch validated.kind {
            case .launch:
                review(.launch(app), details: reason + VyronControlText.openInstalledApp)
            case .wait:
                status = VyronControlText.suggestWait
            case .complete:
                status = VyronControlText.completeVerify
            case .inspect:
                review(.inspect(app), details: reason + VyronControlText.inspectOnlyReview)
            case .activate:
                review(.activate(app), details: reason + VyronControlText.activateApp)
            case .openURL:
                guard let value = validated.url, let url = URL(string: value) else { return }
                review(.openURL(url, app), details: reason + VyronControlText.openSelectedURL(value))
            case .click:
                guard requireFreshSnapshot(), let snapshot, let id = validated.elementID else { return }
                review(
                    .click(app, snapshot.id, id),
                    details: reason
                        + VyronControlText.clickElementReview(id, elementDescription(id))
                )
            case .typeText:
                guard requireFreshSnapshot(), let snapshot, let id = validated.elementID, let text = validated.text
                else { return }
                review(
                    .type(app, snapshot.id, id, text),
                    details: reason
                        + VyronControlText.replaceElementReview(id, elementDescription(id), text)
                )
            case .pressKey:
                guard let key = validated.key else { return }
                review(.key(app, key), details: reason + VyronControlText.sendKeyReview(key.capitalized))
            }
        } catch { self.error = error.localizedDescription }
    }

    func close() {
        stopControlPreview()
        stopTask(reason: VyronControlText.panelClosed)
        stopMonitoring()
        cancelPlanning()
        cancelExecution()
        pendingAction = nil
        performanceTask?.cancel()
        performanceTask = nil
        if let requestID = chatRequestID {
            chat?.finishComputerActivity(requestID: requestID, state: .stopped)
            chat?.reportAgentProgress(
                requestID: requestID,
                state: VyronControlText.goalNotStarted,
                trace: [],
                finished: true
            )
            chatRequestID = nil
        }
    }

    func startTask() {
        guard requireBuiltinModelForComputerTools() else { return }
        if isAgentMode { startAgent(); return }
        guard let chat, !isFollowingTask, !isPlanning, !isExecuting,
            !chat.foregroundRun.isGenerating, !chat.modelDownloads.isActive,
            chat.modelSelection.isConnected, chat.modelSelection.modelIsAvailable,
            accessibilityGranted, let app = selectedApplication
        else { return }
        let goal = plannerInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.count <= VyronTaskPromptLimits.maximumCharacters else {
            error = VyronControlText.taskDescriptionLimit(VyronTaskPromptLimits.localizedMaximumCharacters)
            return
        }
        stopMonitoring()
        if taskGoal != goal { agentFailureCount = 0 }
        taskGoal = goal
        taskApplication = app
        taskEvents = []
        approvedTaskActions = 0
        taskPlanningPasses = 0
        proposal = nil
        pendingAction = nil
        error = nil
        let id = UUID()
        taskRunID = id
        isFollowingTask = true
        chat.computerWork.isPlanningControls = true
        recordTask(VyronControlText.taskStarted(app.name, String(goal.prefix(350))))
        planNextTaskStep(id)
    }

    func stopTask(
        reason: String = VyronControlText.stoppedByUser,
        activityState: ResponseActivity.State = .stopped
    ) {
        guard isFollowingTask else { return }
        isFollowingTask = false
        taskRunID = nil
        taskApplication = nil
        verificationTask?.cancel()
        verificationTask = nil
        cancelPlanningRequest()
        cancelExecution()
        pendingAction = nil
        showConfirmation = false
        proposal = nil
        nextAgentWake = nil
        taskState = reason
        status = reason
        if let requestID = chatRequestID { chat?.finishComputerActivity(requestID: requestID, state: activityState) }
        recordTask(reason)
    }

    func stopVisibleComputerWork() {
        stopTask()
        cancelPlanning()
        cancelExecution()
        pendingAction = nil
        showConfirmation = false
    }

    private func planNextTaskStep(_ runID: UUID) {
        guard taskRunID == runID, isFollowingTask,
            let chat, let app = taskApplication, selectedApplicationID == app.id
        else { return }
        guard taskPlanningPasses < 12, approvedTaskActions < 8 else {
            stopTask(
                reason:
                    VyronControlText.safetyLimit
            )
            return
        }
        let fresh: AutomationSnapshot
        do {
            fresh = try controller.inspect(application: app)
            snapshot = fresh
        } catch {
            self.error = error.localizedDescription
            clearInspection()
            stopTask(reason: VyronControlText.inspectionFailed, activityState: .failed)
            return
        }
        taskPlanningPasses += 1
        taskState = VyronControlText.planningStep(app.name, taskPlanningPasses)
        recordTask(VyronControlText.snapshotPass(taskPlanningPasses))
        proposal = nil
        error = nil
        let planID = UUID()
        planningID = planID
        isPlanning = true
        chat.computerWork.isPlanningControls = true
        let history = taskEvents.suffix(8).map(\.summary).joined(separator: "\n")
        planningTask = Task { @MainActor [weak self, weak chat] in
            guard let self, let chat else { return }
            defer {
                if planningID == planID {
                    planningID = nil
                    isPlanning = false
                    planningTask = nil
                    chat.computerWork.isPlanningControls = isFollowingTask
                }
            }
            do {
                let result = try await chat.modelSelection.builtinClient.proposeControl(
                    model: chat.modelSelection.selectedModel,
                    instruction: taskGoal,
                    snapshot: fresh.text,
                    applicationID: app.id,
                    taskHistory: history
                )
                guard !Task.isCancelled, taskRunID == runID, planningID == planID,
                    selectedApplicationID == app.id, snapshot?.id == fresh.id
                else { return }
                guard snapshotIsFresh else {
                    stopTask(
                        reason:
                            VyronControlText.snapshotExpiredPlanning,
                        activityState: .failed
                    )
                    return
                }
                let validated = try result.validated(
                    expectedApplicationID: app.id,
                    availableElementIDs: availableElementIDs
                )
                proposal = validated
                proposalSnapshotID = fresh.id
                if validated.kind == .complete {
                    isFollowingTask = false
                    taskRunID = nil
                    taskApplication = nil
                    chat.computerWork.isPlanningControls = false
                    taskState = VyronControlText.taskCompleteVerify
                    status = taskState
                    recordTask(taskState + VyronControlText.evidence + validated.explanation)
                } else if validated.kind == .inspect {
                    recordTask(
                        VyronControlText.requestedInspection + String(validated.explanation.prefix(300))
                    )
                    taskState = VyronControlText.readingSelectedApp
                    scheduleTaskRead(runID)
                } else if validated.kind == .wait {
                    let seconds = validated.seconds ?? 5
                    recordTask(VyronControlText.waitingReason(seconds, validated.explanation))
                    scheduleAgentWait(runID, seconds: seconds)
                } else {
                    taskState = VyronControlText.waitingApproval(approvedTaskActions + 1)
                    status = taskState
                    recordTask(
                        VyronControlText.proposedAction(validated.kind.rawValue)
                    )
                }
            } catch {
                if !Task.isCancelled, taskRunID == runID {
                    self.error = error.localizedDescription
                    stopTask(reason: VyronControlText.planningFailed, activityState: .failed)
                }
            }
        }
    }

    private func scheduleTaskRead(_ runID: UUID) {
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, taskRunID == runID, !Task.isCancelled else { return }
            planNextTaskStep(runID)
        }
    }

    private func observeTaskResult(taskID: UUID, before: String, actionSummary: String) {
        guard let app = taskApplication else { return }
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, !Task.isCancelled, taskRunID == taskID, selectedApplicationID == app.id else { return }
            do {
                let result = try controller.inspect(application: app)
                snapshot = result
                let old = Self.normalized(before)
                let new = Self.normalized(result.text)
                let observation =
                    old == new ? VyronControlText.noVisibleChange : Self.changeSummary(before: old, after: new)
                recordTask(VyronControlText.observedAction(approvedTaskActions, actionSummary, observation))
                if isAgentMode { planNextAgentStep(taskID) } else { planNextTaskStep(taskID) }
            } catch {
                self.error = error.localizedDescription
                if isAgentMode {
                    agentFailureCount += 1
                    recordTask(
                        "The action was sent, but its result could not be read: \(String(error.localizedDescription.prefix(400))). Verify the actual app state before considering a repeat."
                    )
                }
                clearInspection()
                stopTask(
                    reason:
                        VyronControlText.resultInspectionFailed,
                    activityState: .failed
                )
            }
        }
    }

    private func recordTask(_ summary: String) {
        taskEvents.append(FollowTaskEvent(summary: String(summary.prefix(900))))
        if taskEvents.count > 32 { taskEvents.removeFirst(taskEvents.count - 32) }
        if let requestID = chatRequestID {
            chat?.reportAgentProgress(
                requestID: requestID,
                state: taskState,
                trace: taskEvents.map(\.summary),
                finished: !isFollowingTask
            )
            if !isFollowingTask { chatRequestID = nil }
        }
    }

    private func clearInspection() {
        snapshot = nil
        proposal = nil
        proposalSnapshotID = nil
        pendingAction = nil
        showConfirmation = false
    }

    private func startAgent() {
        guard requireBuiltinModelForComputerTools() else { return }
        guard let chat, !isFollowingTask, !isPlanning, !isExecuting,
            !chat.foregroundRun.isGenerating, !chat.modelDownloads.isActive,
            chat.modelSelection.isConnected, chat.modelSelection.modelIsAvailable
        else { return }
        if let requestID = chatRequestID, !chat.canStartAgentGoal(requestID) {
            chatRequestID = nil
            return
        }
        guard accessibilityGranted else {
            error = VyronControlText.allowMacControl(permissionLocation)
            return
        }
        let goal = plannerInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.count <= VyronTaskPromptLimits.maximumCharacters else {
            error = VyronControlText.goalDescriptionLimit(VyronTaskPromptLimits.localizedMaximumCharacters)
            return
        }
        guard automaticAppChoice || selectedApplication != nil else {
            error = VyronControlText.chooseApp
            return
        }
        stopMonitoring()
        let resumingFailedGoal = taskGoal == goal && agentFailureCount > 0
        let priorEvents = resumingFailedGoal ? Array(taskEvents.suffix(6)) : []
        if taskGoal != goal { agentFailureCount = 0 }
        taskGoal = goal
        taskApplication = automaticAppChoice ? nil : selectedApplication
        taskEvents = priorEvents
        taskState = VyronControlText.choosingApp
        taskPlanningPasses = 0
        approvedTaskActions = 0
        agentMaximumSteps =
            AgentBudget.forEffort(agentEffort.resolved(for: goal, failureCount: agentFailureCount)).maxSteps
        agentDecision = nil
        agentPlanningRecoveries = 0
        approvedOrigins = []
        clearInspection()
        error = nil
        let runID = UUID()
        taskRunID = runID
        isFollowingTask = true
        chat.computerWork.isPlanningControls = true
        if let requestID = chatRequestID { chat.agentGoalStarted(requestID) }
        recordTask(
            "Goal: \(String(goal.prefix(500))). App choice: \(automaticAppChoice ? "automatic" : (taskApplication?.name ?? "selected app")). Routine actions: \(routineAutonomy ? "automatic after native checks" : "reviewed")."
        )
        if resumingFailedGoal {
            recordTask(
                "Restarting after \(agentFailureCount) failed step(s). Read the actual app state and verify any earlier side effect before considering a repeated action."
            )
        }
        planNextAgentStep(runID)
    }

    private func requireBuiltinModelForComputerTools() -> Bool {
        guard let chat, chat.modelSelection.isBuiltinConnection,
            !chat.modelSelection.connectionOperationInProgress else {
            error =
                VyronControlText.builtinRequired
            return false
        }
        return true
    }

    private func planNextAgentStep(_ runID: UUID) {
        guard isFollowingTask, taskRunID == runID, let chat else { return }
        guard taskPlanningPasses < agentMaximumSteps else {
            stopTask(
                reason:
                    VyronControlText.agentBudget(agentMaximumSteps)
            )
            return
        }
        nextAgentWake = nil
        let catalog = controller.availableApplications().filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let candidates = automaticAppChoice ? catalog : catalog.filter { $0.id == taskApplication?.id }
        guard !candidates.isEmpty else {
            stopTask(reason: VyronControlText.noPermittedApp, activityState: .failed)
            return
        }
        applications = catalog
        if let target = taskApplication, target.processIdentifier > 0 {
            do {
                snapshot = try controller.inspect(application: target)
            } catch {
                self.error = error.localizedDescription
                clearInspection()
                stopTask(reason: VyronControlText.agentStateUnreadable, activityState: .failed)
                return
            }
        }
        let currentSnapshot = snapshot.flatMap { current in
            candidates.contains(where: { $0.id == current.applicationID }) && snapshotIsFresh ? current : nil
        }
        let permittedApps = candidates.map {
            AgentApplication(id: $0.id, name: $0.name, isRunning: $0.processIdentifier > 0)
        }
        let inputSnapshot = currentSnapshot.map {
            AgentSnapshot(applicationID: $0.applicationID, text: $0.text, capturedAt: $0.capturedAt)
        }
        taskPlanningPasses += 1
        let planID = UUID()
        planningID = planID
        isPlanning = true
        chat.computerWork.isPlanningControls = true
        proposal = nil
        taskState = VyronControlText.decidingNextStep
        let history = taskEvents.suffix(10).map(\.summary).joined(separator: "\n")
        planningTask = Task { @MainActor [weak self, weak chat] in
            guard let self, let chat else { return }
            defer {
                if planningID == planID {
                    planningID = nil
                    isPlanning = false
                    planningTask = nil
                    chat.computerWork.isPlanningControls = isFollowingTask
                }
            }
            var decisionReturned = false
            do {
                try Task.checkCancellation()
                let decision = try await chat.modelSelection.builtinClient.planAgent(
                    model: chat.modelSelection.selectedModel,
                    goal: taskGoal,
                    applications: permittedApps,
                    snapshot: inputSnapshot,
                    history: history,
                    effort: agentEffort,
                    failureCount: agentFailureCount
                )
                decisionReturned = true
                guard !Task.isCancelled, taskRunID == runID, planningID == planID else { return }
                agentDecision = decision
                agentMaximumSteps = max(1, decision.budget.maxSteps)
                let proposed = decision.proposal
                proposal = proposed
                let target = candidates.first { $0.id == proposed.applicationID }
                recordTask(
                    VyronControlText.stepDetails(
                        taskPlanningPasses, decision.effort.rawValue, decision.model, proposed.explanation
                    )
                )
                switch proposed.kind {
                case .complete:
                    guard snapshotIsFresh, let current = snapshot, current.applicationID == proposed.applicationID
                    else {
                        throw MacControlError.snapshotExpired
                    }
                    isFollowingTask = false
                    taskRunID = nil
                    taskApplication = nil
                    chat.computerWork.isPlanningControls = false
                    taskState = VyronControlText.taskCompleteVerify
                    status = taskState
                    recordTask(taskState + VyronControlText.evidence + proposed.explanation)
                case .wait:
                    guard let target else { throw MacControlError.applicationUnavailable }
                    routeAgent(to: target)
                    let seconds = proposed.seconds ?? 5
                    scheduleAgentWait(runID, seconds: seconds)
                case .inspect:
                    guard let target else { throw MacControlError.applicationUnavailable }
                    routeAgent(to: target)
                    snapshot = try controller.inspect(application: target)
                    proposal = nil
                    recordTask(VyronControlText.appReadLocally(target.name))
                    scheduleAgentWait(runID, seconds: 0)
                default:
                    guard let target else { throw MacControlError.applicationUnavailable }
                    routeAgent(to: target)
                    let action = try agentAction(proposed, application: target, runID: runID)
                    let verdict = try policy(for: action)
                    switch verdict {
                    case .automatic(let reason) where routineAutonomy:
                        recordTask(VyronControlText.routineAllowed(target.name, reason))
                        pendingAction = action
                        showConfirmation = false
                        taskState = VyronControlText.workingInApp(target.name)
                        executePending(automatic: true)
                    case .automatic(let reason), .review(let reason):
                        pendingAction = action
                        showConfirmation = false
                        taskState = VyronControlText.appReviewNeeded(target.name)
                        status = reason
                        recordTask(VyronControlText.waitingReview(reason))
                    case .refused(let reason):
                        error = reason
                        stopTask(reason: VyronControlText.nextActionNotPermitted, activityState: .failed)
                    }
                }
            } catch {
                if !Task.isCancelled, taskRunID == runID {
                    agentFailureCount += 1
                    recordTask(
                        VyronControlText.verificationFailed(String(error.localizedDescription.prefix(400)))
                    )
                    if !decisionReturned,
                        Self.isRecoverablePlanningError(error),
                        agentPlanningRecoveries < 2,
                        taskPlanningPasses < agentMaximumSteps {
                        agentPlanningRecoveries += 1
                        clearInspection()
                        status = VyronControlText.replanning
                        recordTask(
                            "Planning recovery \(agentPlanningRecoveries) of 2. No action was dispatched for this step; refresh the app catalog and read fresh state before planning again."
                        )
                        scheduleAgentWait(runID, seconds: 0)
                        return
                    }
                    self.error = error.localizedDescription
                    clearInspection()
                    stopTask(reason: VyronControlText.agentVerificationFailed, activityState: .failed)
                }
            }
        }
    }

    private func routeAgent(to app: DesktopApplication) {
        if selectedApplicationID != app.id {
            isRoutingApplication = true
            selectedApplicationID = app.id
            isRoutingApplication = false
            snapshot = nil
            proposalSnapshotID = nil
        }
        taskApplication = app
        if let index = applications.firstIndex(where: { $0.id == app.id }) {
            applications[index] = app
        } else {
            applications.append(app)
        }
    }

    private func agentAction(
        _ proposed: ControlProposal,
        application app: DesktopApplication,
        runID: UUID
    ) throws -> MacActionReview {
        let action: ReviewedMacAction
        var requiredSnapshot: UUID?
        var details = VyronControlText.agentTarget(proposed.explanation, app.name)
        switch proposed.kind {
        case .launch:
            action = .launch(app)
            details += VyronControlText.openInstalledApp
        case .activate:
            action = .activate(app)
            details += VyronControlText.activateApp
        case .openURL:
            guard let value = proposed.url, let url = URL(string: value) else { throw MacControlError.invalidURL }
            action = .openURL(url, app)
            details += VyronControlText.openWebsite(value)
        case .click, .typeText, .pressKey:
            guard let current = snapshot, current.applicationID == app.id, snapshotIsFresh else {
                throw MacControlError.snapshotExpired
            }
            requiredSnapshot = current.id
            if proposed.kind == .pressKey {
                guard let key = proposed.key else { throw MacControlError.unsupportedAction }
                action = .key(app, key)
                details += VyronControlText.sendCommand(key.capitalized)
            } else {
                guard let elementID = proposed.elementID, availableElementIDs.contains(elementID) else {
                    throw MacControlError.elementUnavailable
                }
                details += "\n\(elementDescription(elementID))"
                if proposed.kind == .typeText {
                    guard let text = proposed.text else { throw MacControlError.unsupportedAction }
                    action = .type(app, current.id, elementID, text)
                    details += VyronControlText.replaceField(text)
                } else {
                    action = .click(app, current.id, elementID)
                    details += VyronControlText.clickThisElement
                }
            }
        default: throw MacControlError.unsupportedAction
        }
        return MacActionReview(
            details: details,
            action: action,
            requiredSnapshotID: requiredSnapshot,
            taskRunID: runID,
            stepSummary: "\(proposed.kind.rawValue): \(String(proposed.explanation.prefix(220)))",
            isAgentAction: true
        )
    }

    private func policy(for review: MacActionReview) throws -> AutomationDecision {
        let app: DesktopApplication
        var kind = ""
        var element: NativeElementInfo?
        var text: String?
        var key: String?
        var url: URL?
        switch review.action {
        case .launch(let target): app = target; kind = "launch"
        case .activate(let target): app = target; kind = "activate"
        case .openURL(let targetURL, let browser):
            guard let browser else { return .review(VyronControlText.defaultBrowserReview) }
            app = browser; kind = "openURL"; url = targetURL
        case .click(let target, let snapshotID, let id):
            app = target; kind = "click"
            element = try controller.elementInfo(elementID: id, snapshotID: snapshotID)
        case .type(let target, let snapshotID, let id, let newText):
            app = target; kind = "typeText"; text = newText
            element = try controller.elementInfo(elementID: id, snapshotID: snapshotID)
        case .key(let target, let newKey): app = target; kind = "pressKey"; key = newKey
        case .inspect: return .automatic(VyronControlText.readOnlyInspection)
        }
        return AutomationPolicy.evaluate(
            kind: kind,
            applicationID: app.bundleIdentifier ?? app.id,
            element: element,
            text: text,
            key: key,
            url: url,
            goal: taskGoal,
            approvedOrigins: approvedOrigins
        )
    }

    private func validatePolicyBeforeMutation(_ review: MacActionReview, automatic: Bool) throws {
        switch try policy(for: review) {
        case .refused(let reason): throw AgentPolicyError(reason: reason)
        case .review(let reason) where automatic: throw AgentPolicyError(reason: reason)
        default: break
        }
    }

    private func scheduleAgentWait(_ runID: UUID, seconds: Int) {
        let interval = min(60, max(0, seconds))
        nextAgentWake = interval > 0 ? Date().addingTimeInterval(Double(interval)) : nil
        taskState =
            interval > 0 ? VyronControlText.waitingToRead(interval) : VyronControlText.readingNextState
        if interval > 0 {
            recordTask(
                VyronControlText.waitingExplanation(interval, proposal?.explanation ?? VyronControlText.settling)
            )
        }
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(interval == 0 ? 400 : interval * 1_000)) } catch { return }
            guard let self, taskRunID == runID, !Task.isCancelled else { return }
            if isAgentMode { planNextAgentStep(runID) } else { planNextTaskStep(runID) }
        }
    }

    private static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme.lowercased())://\(host.lowercased())" + (url.port.map { ":\($0)" } ?? "")
    }

    private static func isRecoverablePlanningError(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        if let error = error as? AgentPlanningError, case .invalidDecision = error { return true }
        if let error = error as? ControlPlanningError, case .invalidProposal = error { return true }
        return false
    }

    private func startPerformanceMonitoring() {
        performanceTask?.cancel()
        performanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let sample = try? await systemMonitor.sample(), !Task.isCancelled {
                    systemStatus = sample
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func requireFreshSnapshot() -> Bool {
        guard snapshotIsFresh else {
            error =
                VyronControlText.snapshotTooOld
            return false
        }
        return true
    }

    private func validElementID() -> Int? {
        guard let id = Int(elementID), availableElementIDs.contains(id) else {
            error = VyronControlText.validElement
            return nil
        }
        return id
    }

    private func elementDescription(_ id: Int) -> String {
        snapshot?.text.components(separatedBy: .newlines)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[\(id)] ") }
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(500)) }
            ?? VyronControlText.elementFromSnapshot(id)
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: #"^\s*\[\d+\]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func changeSummary(before: String, after: String) -> String {
        let old = Set(before.components(separatedBy: "\n"))
        let new = Set(after.components(separatedBy: "\n"))
        let added = after.components(separatedBy: "\n").filter { !old.contains($0) }.prefix(3)
        let removed = before.components(separatedBy: "\n").filter { !new.contains($0) }.prefix(2)
        let lines = added.map { "+ " + String($0.prefix(160)) } + removed.map { "− " + String($0.prefix(160)) }
        return lines.isEmpty ? VyronControlText.structureChanged : lines.joined(separator: "\n")
    }
}
