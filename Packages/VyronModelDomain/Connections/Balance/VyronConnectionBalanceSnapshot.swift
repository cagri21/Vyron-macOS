import Foundation

public struct VyronConnectionBalanceSnapshot: Equatable, Sendable {
    public let amounts: [VyronConnectionBalanceAmount]
    public let scope: VyronConnectionBalanceScope
    public let checkedAt: Date

    public init(amounts: [VyronConnectionBalanceAmount], scope: VyronConnectionBalanceScope, checkedAt: Date) {
        self.amounts = amounts
        self.scope = scope
        self.checkedAt = checkedAt
    }
}
