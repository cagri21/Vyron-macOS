struct VyronDevelopmentWorkCycle {
    let maximumRounds: Int
    private(set) var rounds = 0
    private(set) var totalRounds = 0
    private var savedProgressVersion = 0

    init(maximumRounds: Int) {
        self.maximumRounds = maximumRounds
    }

    // Keep each effort's allowance and bound the whole task by the existing twelve-stage scope.
    var canStartRound: Bool {
        totalRounds < maximumRounds * VyronDevelopmentTaskLimits.maximumPlanSteps
    }

    var needsContinuation: Bool { rounds >= maximumRounds }

    mutating func startRound() {
        rounds += 1
        totalRounds += 1
    }

    mutating func continueIfProgress(_ version: Int) -> Bool {
        guard canStartRound, version > savedProgressVersion else { return false }
        rounds = 0
        savedProgressVersion = version
        return true
    }

    mutating func completedStage(progressVersion: Int) {
        rounds = 0
        savedProgressVersion = progressVersion
    }
}
