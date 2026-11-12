import Combine
import Foundation
import VyronCore

@MainActor
final class VyronEstimatedBalancesModel: ObservableObject {
    @Published private(set) var ledgers: [UUID: VyronEstimatedBalanceLedger] = [:]
    @Published private(set) var storageError = false
    private let store: VyronEstimatedBalanceStore?
    private let now: @MainActor () -> Date
    private var eligibleIDs: Set<UUID> = []
    private var generations: [UUID: UUID] = [:]
    private var storageReadable = true
    private var isShutDown = false

    init(store: VyronEstimatedBalanceStore?, now: @escaping @MainActor () -> Date) {
        self.store = store
        self.now = now
        do { ledgers = try store?.load() ?? [:] } catch {
            // Preserve the original file and refuse to replace a ledger that could not be recovered.
            storageReadable = false
            storageError = true
        }
    }

    func configure(profiles: [ModelConnectionProfile]) {
        guard !isShutDown else { return }
        let requested = Set(
            profiles.filter {
                VyronConnectionBalancePolicy.support(for: $0) == .dashboardOnly
            }.map(\.id)
        )
        for id in eligibleIDs.subtracting(requested) { invalidate(id) }
        eligibleIDs = requested
    }

    func state(for id: UUID) -> VyronEstimatedBalanceState? {
        eligibleIDs.contains(id) ? ledgers[id]?.state : nil
    }

    func canSet(_ id: UUID) -> Bool {
        !isShutDown && storageReadable && eligibleIDs.contains(id)
    }

    func setBalance(_ amount: Decimal, for id: UUID) throws {
        guard canSet(id) else { throw VyronEstimatedBalanceError.unavailable }
        guard !amount.isNaN, amount >= 0, amount <= VyronEstimatedBalanceLimits.maximumEnteredUSD else {
            throw VyronEstimatedBalanceError.invalidAmount
        }
        let date = now()
        var updated = ledgers
        updated[id] = VyronEstimatedBalanceLedger(
            state: VyronEstimatedBalanceState(remainingUSD: amount, updatedAt: date, hasUntrackedUsage: false),
            baseline: date,
            receipts: []
        )
        do {
            try store?.save(updated)
            ledgers = updated
            storageError = false
        } catch {
            storageError = true
            throw error
        }
    }

    func invalidate(_ id: UUID) {
        generations[id] = UUID()
        guard ledgers.removeValue(forKey: id) != nil else { return }
        persist()
    }

    /// Capture account identity when constructing a provider; later selection changes do not redirect its cost.
    func usageHandler(for profile: ModelConnectionProfile) -> (@Sendable (VyronOpenAIUsageEvent) async -> Void)? {
        guard !isShutDown, VyronConnectionBalancePolicy.support(for: profile) == .dashboardOnly else { return nil }
        let id = profile.id
        let generation = generations[id] ?? UUID()
        generations[id] = generation
        return { [weak self] event in
            guard event.connectionID == id else { return }
            await self?.record(event, generation: generation)
        }
    }

    func shutdown() { isShutDown = true }

    func finishShutdown(hasUnsettledRequests: Bool) {
        if hasUnsettledRequests {
            for id in eligibleIDs where ledgers[id] != nil {
                ledgers[id]?.state.hasUntrackedUsage = true
                ledgers[id]?.state.updatedAt = max(now(), ledgers[id]?.state.updatedAt ?? now())
            }
            persist()
        }
        shutdown()
    }

    private func record(_ event: VyronOpenAIUsageEvent, generation: UUID) {
        guard !isShutDown, eligibleIDs.contains(event.connectionID),
            generations[event.connectionID] == generation, var ledger = ledgers[event.connectionID]
        else { return }
        let requestReceipt = "request:" + event.requestID.uuidString
        let responseReceipt = event.observation.responseID.map { "response:" + $0 }
        let identifiers = [requestReceipt] + (responseReceipt.map { [$0] } ?? [])
        guard !identifiers.contains(where: ledger.receipts.contains) else { return }
        // A newly entered balance is a fresh baseline. Earlier in-flight work cannot be priced reliably against it.
        guard event.startedAt >= ledger.baseline else {
            ledger.state.hasUntrackedUsage = true
            ledger.state.updatedAt = max(now(), ledger.state.updatedAt)
            ledger.remember(identifiers)
            ledgers[event.connectionID] = ledger
            persist()
            return
        }
        if let cost = VyronOpenAICostEstimator.cost(for: event.observation), !cost.isNaN, cost >= 0 {
            ledger.state.remainingUSD -= cost
        } else {
            ledger.state.hasUntrackedUsage = true
        }
        ledger.state.updatedAt = max(now(), ledger.state.updatedAt)
        ledger.remember(identifiers)
        ledgers[event.connectionID] = ledger
        persist()
    }

    private func persist() {
        guard storageReadable else { storageError = true; return }
        do {
            try store?.save(ledgers)
            storageError = false
        } catch {
            // Retain the updated value in memory so subsequent receipts cannot debit the same request twice.
            storageError = true
        }
    }
}
