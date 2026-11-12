struct VyronDeepSeekBalanceResponse: Decodable {
    let is_available: Bool
    let balance_infos: [VyronDeepSeekBalanceInfo]
}
