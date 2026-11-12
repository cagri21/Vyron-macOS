import VyronCore

enum VyronConnectionBalancePhase: Equatable {
    case idle
    case refreshing
    case ready
    case missingKey
    case credentialUnavailable
    case failed(VyronConnectionBalanceError)
}
