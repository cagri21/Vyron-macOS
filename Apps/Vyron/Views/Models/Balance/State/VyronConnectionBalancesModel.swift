import Combine
import Foundation
import VyronCore

@MainActor
final class VyronConnectionBalancesModel: ObservableObject {
    @Published private(set) var states: [UUID: VyronConnectionBalanceState] = [:]
    let dependencies: VyronConnectionBalanceDependencies
    let estimates: VyronEstimatedBalancesModel
    private var estimateSubscription: AnyCancellable?
    var profiles: [UUID: ModelConnectionProfile] = [:]
    var activeID: UUID?
    var isStarted = false
    var isShutDown = false
    var generations: [UUID: UUID] = [:]
    var requests: [UUID: Task<Void, Never>] = [:]
    var responseTasks: [UUID: Task<Void, Never>] = [:]
    var failures: [UUID: Int] = [:]
    var automaticBlocked: Set<UUID> = []
    var providerRetryDates: [UUID: Date] = [:]
    var automaticRetryDates: [UUID: Date] = [:]
    var pollTask: Task<Void, Never>?

    init(dependencies: VyronConnectionBalanceDependencies, estimateStore: VyronEstimatedBalanceStore? = nil) {
        self.dependencies = dependencies
        estimates = VyronEstimatedBalancesModel(store: estimateStore, now: dependencies.clock.now)
        estimateSubscription = estimates.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func state(for id: UUID) -> VyronConnectionBalanceState {
        states[id] ?? VyronConnectionBalanceState(support: .unsupported, snapshot: nil, phase: .idle, lastAttempt: nil)
    }

    func configure(profiles requested: [ModelConnectionProfile], activeID requestedActiveID: UUID?) {
        guard !isShutDown else { return }
        estimates.configure(profiles: requested)
        var updated: [UUID: ModelConnectionProfile] = [:]
        for profile in requested { updated[profile.id] = profile }
        let previousActive = activeID
        if previousActive != requestedActiveID, let previousActive { cancel(previousActive) }
        for id in profiles.keys where updated[id] == nil {
            cancel(id)
            states.removeValue(forKey: id)
            failures.removeValue(forKey: id)
            automaticBlocked.remove(id)
            generations.removeValue(forKey: id)
            providerRetryDates.removeValue(forKey: id)
            automaticRetryDates.removeValue(forKey: id)
        }
        var changed: Set<UUID> = []
        for (id, profile) in updated {
            let support = VyronConnectionBalancePolicy.support(for: profile)
            guard profiles[id] == nil || state(for: id).support != support else { continue }
            cancel(id)
            states[id] = VyronConnectionBalanceState(
                support: support,
                snapshot: nil,
                phase: .idle,
                lastAttempt: nil
            )
            failures.removeValue(forKey: id)
            automaticBlocked.remove(id)
            providerRetryDates.removeValue(forKey: id)
            automaticRetryDates.removeValue(forKey: id)
            changed.insert(id)
        }
        profiles = updated
        activeID = requestedActiveID.flatMap { updated[$0] == nil ? nil : $0 }
        if previousActive != activeID {
            pollTask?.cancel()
            pollTask = nil
        }
        if isStarted, let id = activeID, previousActive != id || changed.contains(id) {
            resumeActiveRefresh(id)
        }
    }

    func start() {
        guard !isStarted, !isShutDown else { return }
        isStarted = true
        if let activeID { beginRefresh(activeID, manual: false) }
    }

    func canRefresh(_ id: UUID) -> Bool {
        isStarted && !isShutDown && profiles[id] != nil && state(for: id).support.canFetch && requests[id] == nil
            && (providerRetryDates[id].map { $0 <= dependencies.clock.now() } ?? true)
    }

    func refresh(_ id: UUID) { beginRefresh(id, manual: true) }

    func credentialChanged(_ id: UUID) {
        guard !isShutDown, let profile = profiles[id] else { return }
        estimates.invalidate(id)
        cancel(id)
        failures.removeValue(forKey: id)
        automaticBlocked.remove(id)
        providerRetryDates.removeValue(forKey: id)
        automaticRetryDates.removeValue(forKey: id)
        states[id] = VyronConnectionBalanceState(
            support: VyronConnectionBalancePolicy.support(for: profile),
            snapshot: nil,
            phase: .idle,
            lastAttempt: nil
        )
        if isStarted, activeID == id { beginRefresh(id, manual: false) }
    }

    func responseCompleted(_ id: UUID?) {
        guard let id, isStarted, !isShutDown, state(for: id).support.canFetch,
            profiles[id] != nil, !automaticBlocked.contains(id), responseTasks[id] == nil
        else { return }
        if let date = automaticRetryDates[id], date > dependencies.clock.now() { return }
        let clock = dependencies.clock
        let generation = generations[id]
        responseTasks[id] = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(.seconds(VyronConnectionBalanceTiming.responseDelaySeconds))
                guard let self, !Task.isCancelled, !self.isShutDown, self.generations[id] == generation else { return }
                self.responseTasks[id] = nil
                if let last = self.state(for: id).lastAttempt,
                    clock.now().timeIntervalSince(last) < VyronConnectionBalanceTiming.responseDelaySeconds {
                    return
                }
                self.beginRefresh(id, manual: false)
            } catch {
                guard let self, !self.isShutDown, self.generations[id] == generation else { return }
                self.responseTasks[id] = nil
                if !(error is CancellationError), !Task.isCancelled { self.timerFailed(id) }
            }
        }
    }

    func isStale(for id: UUID) -> Bool {
        guard let snapshot = state(for: id).snapshot else { return false }
        if case .failed = state(for: id).phase { return true }
        if state(for: id).phase == .credentialUnavailable { return true }
        let age = dependencies.clock.now().timeIntervalSince(snapshot.checkedAt)
        return age < 0 || age > VyronConnectionBalanceTiming.staleSeconds
    }

    func billingURL(for id: UUID) -> URL? {
        switch state(for: id).support {
        case .deepSeek: URL(string: "https://platform.deepseek.com/usage")
        case .openRouter: URL(string: "https://openrouter.ai/credits")
        case .dashboardOnly: URL(string: "https://platform.openai.com/settings/organization/billing/overview")
        case .local, .unsupported: nil
        }
    }

    func shutdown(waitForUsage: Bool = false) {
        guard !isShutDown else { return }
        isShutDown = true
        if !waitForUsage { estimates.shutdown() }
        pollTask?.cancel()
        pollTask = nil
        for id in Array(requests.keys) { cancel(id) }
        for task in responseTasks.values { task.cancel() }
        responseTasks.removeAll()
    }

    func cancel(_ id: UUID) {
        generations[id] = UUID()
        requests.removeValue(forKey: id)?.cancel()
        responseTasks.removeValue(forKey: id)?.cancel()
        if activeID == id {
            pollTask?.cancel()
            pollTask = nil
        }
        if state(for: id).phase == .refreshing {
            states[id]?.phase = state(for: id).snapshot == nil ? .idle : .ready
        }
    }

    func timerFailed(_ id: UUID) {
        guard profiles[id] != nil else { return }
        states[id]?.phase = .failed(.temporarilyUnavailable)
    }
}

extension VyronConnectionBalancesModel {
    func beginRefresh(_ id: UUID, manual: Bool) {
        guard canRefresh(id), manual || !automaticBlocked.contains(id), let profile = profiles[id] else { return }
        if !manual, let date = automaticRetryDates[id], date > dependencies.clock.now() { return }
        if manual { automaticBlocked.remove(id) }
        if activeID == id {
            pollTask?.cancel()
            pollTask = nil
        }
        let generation = UUID()
        generations[id] = generation
        responseTasks.removeValue(forKey: id)?.cancel()
        states[id]?.phase = .refreshing
        states[id]?.lastAttempt = dependencies.clock.now()
        requests[id] = Task { @MainActor [weak self, dependencies] in
            guard let self, self.ownsRequest(id, generation: generation), !Task.isCancelled else { return }
            do {
                let key: String
                do {
                    key = try dependencies.credential(id)
                } catch {
                    self.requests[id] = nil
                    self.states[id]?.phase = .credentialUnavailable
                    self.automaticBlocked.insert(id)
                    return
                }
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finishFailure(.missingKey, id: id, generation: generation)
                    return
                }
                let snapshot = try await dependencies.repository.fetchBalance(for: profile, apiKey: key)
                guard self.ownsRequest(id, generation: generation), !Task.isCancelled else { return }
                self.requests[id] = nil
                self.failures.removeValue(forKey: id)
                self.automaticBlocked.remove(id)
                self.providerRetryDates.removeValue(forKey: id)
                self.automaticRetryDates.removeValue(forKey: id)
                self.states[id]?.snapshot = snapshot
                self.states[id]?.phase = .ready
                self.schedulePoll(id, after: VyronConnectionBalanceTiming.refreshSeconds)
            } catch is CancellationError {
                guard self.ownsRequest(id, generation: generation) else { return }
                self.requests[id] = nil
                self.states[id]?.phase = self.state(for: id).snapshot == nil ? .idle : .ready
            } catch {
                guard self.ownsRequest(id, generation: generation), !Task.isCancelled else { return }
                if let advised = error as? VyronConnectionBalanceRetryFailure {
                    if let date = advised.retryAfter, date > dependencies.clock.now() {
                        self.providerRetryDates[id] = date
                    }
                    self.finishFailure(advised.error, id: id, generation: generation)
                    if let retryAfter = advised.retryAfter, self.activeID == id,
                        !self.automaticBlocked.contains(id) {
                        let remaining = retryAfter.timeIntervalSince(dependencies.clock.now())
                        let delay = VyronConnectionBalanceTiming.retrySeconds(
                            failureCount: self.failures[id] ?? 1
                        )
                        if remaining.isFinite, remaining > delay {
                            self.schedulePoll(id, after: remaining)
                        }
                    }
                    return
                }
                let failure = error as? VyronConnectionBalanceError ?? .connectionFailed
                self.finishFailure(failure, id: id, generation: generation)
            }
        }
    }

    private func ownsRequest(_ id: UUID, generation: UUID) -> Bool {
        !isShutDown && profiles[id] != nil && generations[id] == generation
    }

    private func finishFailure(_ error: VyronConnectionBalanceError, id: UUID, generation: UUID) {
        guard ownsRequest(id, generation: generation) else { return }
        requests[id] = nil
        switch error {
        case .missingKey:
            states[id]?.snapshot = nil
            states[id]?.phase = .missingKey
            automaticBlocked.insert(id)
        case .authenticationFailed:
            states[id]?.phase = .failed(error)
            automaticBlocked.insert(id)
        case .unsupported:
            states[id]?.snapshot = nil
            states[id]?.phase = .failed(error)
            automaticBlocked.insert(id)
        case .noKeyLimit:
            states[id]?.snapshot = nil
            states[id]?.phase = .failed(error)
            failures.removeValue(forKey: id)
            schedulePoll(id, after: VyronConnectionBalanceTiming.refreshSeconds)
        case .rateLimited, .temporarilyUnavailable, .invalidResponse, .connectionFailed:
            states[id]?.phase = .failed(error)
            let count = min(4, (failures[id] ?? 0) + 1)
            failures[id] = count
            let seconds = VyronConnectionBalanceTiming.retrySeconds(failureCount: count)
            automaticRetryDates[id] = dependencies.clock.now().addingTimeInterval(seconds)
            schedulePoll(id, after: seconds)
        }
    }

    func resumeActiveRefresh(_ id: UUID) {
        if let date = [providerRetryDates[id], automaticRetryDates[id]].compactMap({ $0 }).max(),
            date > dependencies.clock.now() {
            schedulePoll(id, after: date.timeIntervalSince(dependencies.clock.now()))
        } else {
            beginRefresh(id, manual: false)
        }
    }

    private func schedulePoll(_ id: UUID, after seconds: TimeInterval) {
        guard isStarted, !isShutDown, activeID == id, !automaticBlocked.contains(id) else { return }
        pollTask?.cancel()
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int64.max / 2) else {
            pollTask = nil
            automaticBlocked.insert(id)
            return
        }
        let generation = generations[id]
        let clock = dependencies.clock
        pollTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(.seconds(seconds))
                guard let self, !self.isShutDown, !Task.isCancelled, self.activeID == id,
                    self.generations[id] == generation
                else { return }
                self.pollTask = nil
                self.beginRefresh(id, manual: false)
            } catch {
                guard let self, !self.isShutDown, self.generations[id] == generation else { return }
                if !(error is CancellationError), !Task.isCancelled { self.timerFailed(id) }
            }
        }
    }
}
