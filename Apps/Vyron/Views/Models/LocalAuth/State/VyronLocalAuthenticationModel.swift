import Combine
import Foundation
import VyronCore

@MainActor
final class VyronLocalAuthenticationModel: ObservableObject {
    @Published private(set) var status = VyronLocalAuthStatus.notConfigured
    @Published private(set) var failure: VyronLocalAuthError?
    private let backup: any VyronLocalCredentialBacking
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var mutations: [UUID: UUID] = [:]
    private var settledStatus = VyronLocalAuthStatus.notConfigured
    private var stopped = false

    init(backup: any VyronLocalCredentialBacking) {
        self.backup = backup
    }

    func mutationSnapshot(connectionIDs: [UUID]) -> [UUID: UUID] {
        for id in connectionIDs where mutations[id] == nil { mutations[id] = UUID() }
        return mutations.filter { connectionIDs.contains($0.key) }
    }

    func matchesMutation(connectionID: UUID, token: UUID?) -> Bool {
        token != nil && mutations[connectionID] == token
    }

    func invalidate(connectionID: UUID) {
        mutations[connectionID] = UUID()
        cancelCurrentRequest()
    }

    func synchronize(connectionIDs: [UUID], actions: VyronLocalCredentialRestoreActions) {
        guard !stopped else { return }
        cancelCurrentRequest()
        let requestID = generation
        status = .connecting
        failure = nil
        task = Task { @MainActor [weak self, backup] in
            do {
                let result = try await backup.synchronize(connectionIDs: connectionIDs)
                try Task.checkCancellation()
                guard let self, self.isCurrent(requestID) else { return }
                var restored: [UUID] = []
                for candidate in result.restorations {
                    guard self.isCurrent(requestID), !Task.isCancelled else { return }
                    if try actions.restore(candidate) { restored.append(candidate.connectionID) }
                }
                self.status = result.status
                self.settledStatus = result.status
                if !restored.isEmpty { await actions.didRestore(restored) }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.isCurrent(requestID), !Task.isCancelled else { return }
                self.fail(error)
            }
            guard let self, self.isCurrent(requestID) else { return }
            self.task = nil
        }
    }

    func remove(connectionID: UUID) async {
        guard !stopped else { return }
        cancelCurrentRequest()
        let requestID = generation
        status = .connecting
        failure = nil
        let removal = Task { @MainActor [weak self, backup] in
            do {
                let result = try await backup.remove(connectionID: connectionID)
                try Task.checkCancellation()
                guard let self, self.isCurrent(requestID) else { return }
                self.status = result
                self.settledStatus = result
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.isCurrent(requestID), !Task.isCancelled else { return }
                self.fail(error)
            }
            guard let self, self.isCurrent(requestID) else { return }
            self.task = nil
        }
        task = removal
        await removal.value
    }

    @discardableResult
    func shutdown() -> Task<Void, Never>? {
        let pending = task
        stopped = true
        cancelCurrentRequest()
        return pending
    }

    private func cancelCurrentRequest() {
        generation = UUID()
        task?.cancel()
        task = nil
        if status == .connecting { status = settledStatus }
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        !stopped && generation == requestID
    }

    private func fail(_ error: Error) {
        failure = (error as? VyronLocalAuthError) ?? .unavailable
        status = .unavailable
        settledStatus = .unavailable
    }
}
