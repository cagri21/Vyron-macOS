import Foundation

public struct VyronConnectionBalanceAmount: Equatable, Sendable {
    public let currency: String
    public let amount: Decimal

    public init(currency: String, amount: Decimal) {
        self.currency = currency
        self.amount = amount
    }
}
