import Foundation

struct VyronEstimatedBalanceLedger: Codable, Equatable, Sendable {
    var state: VyronEstimatedBalanceState
    let baseline: Date
    var receipts: [String]

    static let maximumReceipts = 4_096

    mutating func remember(_ identifiers: [String]) {
        receipts.append(contentsOf: identifiers)
        if receipts.count > Self.maximumReceipts {
            receipts.removeFirst(receipts.count - Self.maximumReceipts)
        }
    }
}
