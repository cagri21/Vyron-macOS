import Foundation

struct VyronEstimatedBalanceDocument: Codable {
    let version: Int
    let records: [VyronEstimatedBalanceRecord]
}
