import Foundation

extension VyronConnectionBalancesModel {
    var estimateStorageError: Bool { estimates.storageError }

    func estimatedBalance(for id: UUID) -> VyronEstimatedBalanceState? { estimates.state(for: id) }

    func canSetEstimatedBalance(for id: UUID) -> Bool { estimates.canSet(id) }

    func setEstimatedBalance(_ amount: Decimal, for id: UUID) throws {
        try estimates.setBalance(amount, for: id)
    }
}
