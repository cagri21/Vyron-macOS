import Foundation
import VyronCore

struct VyronConnectionBalanceState {
    let support: VyronConnectionBalanceSupport
    var snapshot: VyronConnectionBalanceSnapshot?
    var phase: VyronConnectionBalancePhase
    var lastAttempt: Date?

    var isRefreshing: Bool { phase == .refreshing }
}
