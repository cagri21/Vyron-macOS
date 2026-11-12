import Foundation

struct VyronEstimatedBalanceRecord: Codable {
    let connectionID: UUID
    let ledger: VyronEstimatedBalanceLedger
}
