import Foundation
import VyronModelDomain

struct VyronOpenRouterKeyBalance: Decodable {
    let limit_remaining: Decimal?

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.limit_remaining) else { throw VyronConnectionBalanceError.invalidResponse }
        limit_remaining = try values.decodeIfPresent(Decimal.self, forKey: .limit_remaining)
    }
}
