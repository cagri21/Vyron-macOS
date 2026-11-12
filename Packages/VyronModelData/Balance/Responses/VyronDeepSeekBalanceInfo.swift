import Foundation

struct VyronDeepSeekBalanceInfo: Decodable {
    let currency: String
    let total_balance: String
    let granted_balance: String
    let topped_up_balance: String
}
