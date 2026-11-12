import Foundation

struct VyronEstimatedBalanceState: Codable, Equatable, Sendable {
    var remainingUSD: Decimal
    var updatedAt: Date
    var hasUntrackedUsage: Bool
}
