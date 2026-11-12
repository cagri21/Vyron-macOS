import XCTest
@testable import VyronCore

final class VyronDevelopmentWorkCycleTests: XCTestCase {
    func testEffortRoundAllowancesRemainBounded() {
        XCTAssertEqual(AgentEffort.quick.developmentBudget.maximumToolRounds, 12)
        XCTAssertEqual(AgentEffort.balanced.developmentBudget.maximumToolRounds, 20)
        for effort in [AgentEffort.deep, .extraHigh, .maximum, .ultra] {
            XCTAssertEqual(effort.developmentBudget.maximumToolRounds, 30)
        }
    }

    func testContinuationRequiresProgressSinceThePreviousCycle() {
        var cycle = VyronDevelopmentWorkCycle(maximumRounds: 3)
        for _ in 0..<3 { cycle.startRound() }

        XCTAssertTrue(cycle.needsContinuation)
        XCTAssertFalse(cycle.continueIfProgress(0))
        XCTAssertEqual(cycle.rounds, 3)
        XCTAssertTrue(cycle.continueIfProgress(1))
        XCTAssertEqual(cycle.rounds, 0)
        XCTAssertEqual(cycle.totalRounds, 3)

        for _ in 0..<3 { cycle.startRound() }
        XCTAssertFalse(cycle.continueIfProgress(1))
        XCTAssertTrue(cycle.continueIfProgress(2))
        XCTAssertEqual(cycle.rounds, 0)
        XCTAssertEqual(cycle.totalRounds, 6)
    }

    func testCompletedStagesCannotResetTheOverallRoundAllowance() {
        let maximumRounds = 2
        let overallAllowance = maximumRounds * VyronDevelopmentTaskLimits.maximumPlanSteps
        var cycle = VyronDevelopmentWorkCycle(maximumRounds: maximumRounds)

        for version in 1...overallAllowance {
            XCTAssertTrue(cycle.canStartRound)
            cycle.startRound()
            cycle.completedStage(progressVersion: version)
            XCTAssertEqual(cycle.rounds, 0)
        }

        XCTAssertEqual(cycle.totalRounds, overallAllowance)
        XCTAssertFalse(cycle.canStartRound)
        XCTAssertFalse(cycle.continueIfProgress(overallAllowance + 1))
    }

    func testCompletedStageProgressCannotRenewALaterCycleWithoutFurtherProgress() {
        var cycle = VyronDevelopmentWorkCycle(maximumRounds: 2)
        cycle.startRound()
        cycle.completedStage(progressVersion: 4)
        for _ in 0..<2 { cycle.startRound() }

        XCTAssertTrue(cycle.needsContinuation)
        XCTAssertFalse(cycle.continueIfProgress(4))
        XCTAssertTrue(cycle.continueIfProgress(5))
    }

    func testProgressingCyclesStillReachTheOverallTaskLimit() {
        var cycle = VyronDevelopmentWorkCycle(maximumRounds: 2)
        let overallAllowance = 2 * VyronDevelopmentTaskLimits.maximumPlanSteps
        var version = 0

        for _ in 0..<overallAllowance {
            XCTAssertTrue(cycle.canStartRound)
            cycle.startRound()
            version += 1
            if cycle.needsContinuation {
                XCTAssertEqual(cycle.continueIfProgress(version), cycle.totalRounds < overallAllowance)
            }
        }

        XCTAssertEqual(cycle.totalRounds, overallAllowance)
        XCTAssertTrue(cycle.needsContinuation)
        XCTAssertFalse(cycle.continueIfProgress(version + 1))
    }
}
