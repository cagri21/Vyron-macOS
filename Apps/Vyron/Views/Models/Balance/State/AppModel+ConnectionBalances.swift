import Combine

extension AppModel {
    func configureConnectionBalanceObservers() {
        modelSelection.$connectionProfiles.combineLatest(modelSelection.$activeConnectionID)
            .sink { [weak balances = connectionBalances] profiles, activeID in
                balances?.configure(profiles: profiles, activeID: activeID)
            }
            .store(in: &connectionBalanceSubscriptions)
    }
}
