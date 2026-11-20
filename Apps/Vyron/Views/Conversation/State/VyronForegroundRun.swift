import Combine
import Foundation
import VyronCore
import VyronModelDomain

@MainActor
final class VyronForegroundRun: ObservableObject {
    @Published private(set) var activeResponse: VyronResponseIdentity?
    @Published private(set) var isDeveloping = false
    @Published private(set) var stoppingDevelopmentConversationID: UUID?
    @Published private var backgroundResponses: [UUID: VyronBackgroundConversationRun] = [:]

    private(set) var activeBalanceConnectionID: UUID?
    private var route: VyronForegroundRunRoute = .foregroundOnly
    private var generationTasks: [UUID: Task<Void, Never>] = [:]
    private var steeringTasks: [UUID: Task<Void, Never>] = [:]
    private var lastSteeringTask: Task<Void, Never>?
    private var stoppingDevelopmentTask: Task<Void, Never>?
    private var stoppingDevelopmentID: UUID?

    var activeGeneration: UUID? { activeResponse?.generationID }
    var isGenerating: Bool { activeResponse != nil }
    var isStoppingDevelopment: Bool { stoppingDevelopmentConversationID != nil }
    var isIdle: Bool { !isGenerating && !isStoppingDevelopment }
    var canContinueInBackground: Bool { route.canContinueInBackground }
    var hasBackgroundResponses: Bool { !backgroundResponses.isEmpty }
    var backgroundResponseIdentities: [VyronResponseIdentity] { backgroundResponses.values.map(\.response) }
    var activeSteeringInbox: VyronSteeringInbox? { route.steering?.inbox }
    var activeSkillTools: VyronSkillResourceTools? { route.steering?.skills }
    var activePendingSteeringIDs: Set<UUID> { route.steering?.pendingMessageIDs ?? [] }
    var developmentResponse: VyronResponseIdentity? {
        if route.steering != nil { return activeResponse }
        return backgroundResponses.values.first { $0.route.steering != nil }?.response
    }

    func begin(_ response: VyronResponseIdentity, balanceConnectionID: UUID? = nil) {
        guard activeResponse == nil, backgroundResponses[response.conversationID] == nil else { return }
        activeBalanceConnectionID = balanceConnectionID
        activeResponse = response
    }

    func start(
        _ response: VyronResponseIdentity,
        route: VyronForegroundRunRoute = .foregroundOnly,
        operation: @escaping @MainActor () async -> Void
    ) {
        let id = response.generationID
        guard activeResponse == response, generationTasks[id] == nil else { return }
        self.route = route
        generationTasks[id] = Task { @MainActor [weak self] in
            defer { self?.generationTasks[id] = nil }
            guard self?.owns(response) == true, !Task.isCancelled else { return }
            await operation()
        }
    }

    func beginDevelopment(_ response: VyronResponseIdentity) {
        if activeResponse == response {
            isDeveloping = true
        } else if owns(response) {
            backgroundResponses[response.conversationID]?.isDeveloping = true
        }
    }

    func setBalanceConnection(_ id: UUID?, for response: VyronResponseIdentity) {
        if activeResponse == response {
            activeBalanceConnectionID = id
        } else if backgroundResponses[response.conversationID]?.response == response {
            backgroundResponses[response.conversationID]?.balanceConnectionID = id
        }
    }

    func complete(_ generationID: UUID) {
        guard activeGeneration == generationID else { return }
        releaseResponse()
    }

    @discardableResult
    func stop(
        refreshDevelopment: @escaping @MainActor () async -> Void = {},
        didSettle: @escaping @MainActor () -> Void = {}
    ) -> Bool {
        guard let response = activeResponse else { return false }
        let task = generationTasks[response.generationID]
        let shouldSettle = isDeveloping && task != nil
        if shouldSettle, let task {
            settleStoppedDevelopment(
                task,
                conversationID: response.conversationID,
                refresh: refreshDevelopment,
                didSettle: didSettle
            )
        }
        releaseResponse()
        task?.cancel()
        return shouldSettle
    }

    func shutdown() -> [Task<Void, Never>] {
        releaseResponse()
        for run in backgroundResponses.values { finishSteering(run.route) }
        backgroundResponses.removeAll()
        for task in generationTasks.values { task.cancel() }
        var pending = Array(generationTasks.values) + Array(steeringTasks.values)
        if let stoppingDevelopmentTask { pending.append(stoppingDevelopmentTask) }
        return pending
    }

    func response(in conversationID: UUID) -> VyronResponseIdentity? {
        if let activeResponse, activeResponse.conversationID == conversationID { return activeResponse }
        return backgroundResponses[conversationID]?.response
    }

    func response(forGeneration generationID: UUID) -> VyronResponseIdentity? {
        if activeResponse?.generationID == generationID { return activeResponse }
        return backgroundResponses.values.first { $0.response.generationID == generationID }?.response
    }

    func isDevelopmentResponse(_ response: VyronResponseIdentity) -> Bool {
        steering(for: response) != nil
    }

    func steering(for response: VyronResponseIdentity) -> VyronForegroundSteering? {
        if activeResponse == response { return route.steering }
        guard let run = backgroundResponses[response.conversationID], run.response == response else { return nil }
        return run.route.steering
    }

    func owns(_ response: VyronResponseIdentity) -> Bool {
        self.response(in: response.conversationID) == response
    }

    func moveResponseToBackground() -> Bool {
        guard canContinueInBackground, let response = activeResponse,
            generationTasks[response.generationID] != nil
        else { return false }
        backgroundResponses[response.conversationID] = VyronBackgroundConversationRun(
            response: response, balanceConnectionID: activeBalanceConnectionID,
            route: route, isDeveloping: isDeveloping
        )
        clearSelection()
        return true
    }

    func bringResponseToForeground(in conversationID: UUID) {
        guard activeResponse == nil, let run = backgroundResponses.removeValue(forKey: conversationID) else { return }
        begin(run.response, balanceConnectionID: run.balanceConnectionID)
        route = run.route
        isDeveloping = run.isDeveloping
    }

    func removeBackgroundResponse(_ response: VyronResponseIdentity) -> VyronBackgroundConversationRun? {
        guard let run = backgroundResponses[response.conversationID], run.response == response else { return nil }
        finishSteering(run.route)
        return backgroundResponses.removeValue(forKey: response.conversationID)
    }

    func enqueueSteering(generationID: UUID, operation: @escaping @MainActor () async -> Void) {
        guard let response = response(forGeneration: generationID), isDevelopmentResponse(response) else { return }
        let id = UUID()
        let previous = lastSteeringTask
        let task = Task { @MainActor [weak self] in
            defer { self?.steeringTasks[id] = nil }
            await previous?.value
            guard self?.isDevelopmentResponse(response) == true, !Task.isCancelled else { return }
            await operation()
        }
        lastSteeringTask = task
        steeringTasks[id] = task
    }

    private func finishSteering(_ route: VyronForegroundRunRoute) {
        guard let steering = route.steering else { return }
        for task in steeringTasks.values { task.cancel() }
        lastSteeringTask = nil
        steering.pendingMessageIDs.removeAll()
        Task { await steering.inbox.close() }
    }

    func streamResponse(
        _ response: VyronResponseIdentity,
        receive: @escaping @MainActor @Sendable (String) -> Void,
        perform: (AsyncStream<String>.Continuation) async throws -> String
    ) async throws -> String {
        try Task.checkCancellation()
        guard owns(response) else { throw CancellationError() }
        let stream = AsyncStream<String>.makeStream()
        async let drain: Void = drainTokens(stream.stream, response: response, receive: receive)
        let result: String
        do {
            result = try await perform(stream.continuation)
        } catch {
            stream.continuation.finish()
            await drain
            throw error
        }
        stream.continuation.finish()
        await drain
        try Task.checkCancellation()
        guard owns(response) else { throw CancellationError() }
        return result
    }

    private func drainTokens(
        _ tokens: AsyncStream<String>,
        response: VyronResponseIdentity,
        receive: @MainActor @Sendable (String) -> Void
    ) async {
        for await token in tokens {
            guard owns(response), !Task.isCancelled else { return }
            receive(token)
        }
    }

    private func releaseResponse() {
        finishSteering(route)
        clearSelection()
    }

    private func clearSelection() {
        route = .foregroundOnly
        activeBalanceConnectionID = nil
        if isDeveloping { isDeveloping = false }
        if activeResponse != nil { activeResponse = nil }
    }

    private func settleStoppedDevelopment(
        _ task: Task<Void, Never>,
        conversationID: UUID,
        refresh: @escaping @MainActor () async -> Void,
        didSettle: @escaping @MainActor () -> Void
    ) {
        let stoppingID = UUID()
        stoppingDevelopmentID = stoppingID
        stoppingDevelopmentConversationID = conversationID
        stoppingDevelopmentTask = Task { @MainActor [weak self] in
            await task.value
            guard let self, stoppingDevelopmentID == stoppingID else { return }
            await refresh()
            guard stoppingDevelopmentID == stoppingID else { return }
            stoppingDevelopmentConversationID = nil
            stoppingDevelopmentID = nil
            stoppingDevelopmentTask = nil
            didSettle()
        }
    }
}
