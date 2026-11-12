import Foundation
import VyronCore

struct VyronConnectionBalanceDependencies {
    let repository: any VyronConnectionBalanceProviding
    let credential: @MainActor (UUID) throws -> String
    let clock: VyronConnectionBalanceClock
}
