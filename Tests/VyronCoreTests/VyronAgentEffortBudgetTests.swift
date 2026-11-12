import XCTest
@testable import VyronCore

final class VyronAgentEffortBudgetTests: XCTestCase {
    func testAllSixDevelopmentProfilesHaveDistinctBoundedOutputAllowances() {
        let efforts: [AgentEffort] = [.quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
        XCTAssertEqual(efforts.map { $0.developmentBudget.outputTokens }, [2_048, 4_096, 6_144, 8_192, 10_240, 12_288])
        XCTAssertEqual(efforts.map { $0.developmentBudget.maximumToolRounds }, [12, 20, 30, 30, 30, 30])
        XCTAssertEqual(AgentEffort.automatic.developmentBudget, AgentEffort.balanced.developmentBudget)
        XCTAssertTrue(efforts.allSatisfy { $0.developmentBudget.maximumToolRounds <= 30 })
    }

    func testMacControlProfilesPreserveExistingLimitsWhileAddingBoundedHigherOutput() {
        let efforts: [AgentEffort] = [.quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
        let budgets = efforts.map(AgentBudget.forEffort)
        XCTAssertEqual(budgets.map(\.contextTokens), [16_384, 32_768, 32_768, 32_768, 32_768, 32_768])
        XCTAssertEqual(budgets.map(\.outputTokens), [384, 768, 1_536, 2_048, 2_560, 3_072])
        XCTAssertEqual(budgets.map(\.snapshotBytes), [4_000, 8_000, 12_000, 14_000, 16_000, 18_000])
        XCTAssertEqual(budgets.map(\.historyBytes), [1_024, 2_048, 4_096, 4_096, 4_096, 4_096])
        XCTAssertEqual(budgets.map(\.maxSteps), [6, 12, 20, 20, 20, 20])
        XCTAssertEqual(AgentBudget.forEffort(.automatic), AgentBudget.forEffort(.balanced))
    }

    func testFittingEveryProfileRespectsGlobalContextAndKeepsItsExecutionAllowance() throws {
        for effort in AgentEffort.allCases {
            let original = AgentBudget.forEffort(effort)
            for inputBytes in [1_000, 20_000] {
                let fitted = try original.fitting(baseInputBytes: inputBytes)
                XCTAssertLessThanOrEqual(fitted.contextTokens, 32_768)
                XCTAssertEqual(fitted.outputTokens, original.outputTokens)
                XCTAssertEqual(fitted.maxSteps, original.maxSteps)
                XCTAssertLessThanOrEqual(fitted.snapshotBytes, original.snapshotBytes)
                XCTAssertLessThanOrEqual(fitted.historyBytes, original.historyBytes)
                XCTAssertLessThanOrEqual(
                    inputBytes + fitted.snapshotBytes + fitted.historyBytes + fitted.outputTokens + 2_048,
                    fitted.contextTokens
                )
            }
            XCTAssertThrowsError(try original.fitting(baseInputBytes: 32_768)) {
                XCTAssertEqual($0 as? AgentPlanningError, .inputTooLarge)
            }
        }
    }

    func testExplicitManualEffortIsNeverSilentlyResolvedToAnotherLevel() {
        for effort in [AgentEffort.quick, .balanced, .deep, .extraHigh, .maximum, .ultra] {
            XCTAssertEqual(effort.resolved(for: "Open Safari"), effort)
            XCTAssertEqual(effort.resolved(for: "Debug and refactor the entire project.", failureCount: 100), effort)
        }
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Open Safari"), .quick)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Explain this project."), .balanced)
        XCTAssertEqual(AgentEffort.automatic.resolved(for: "Debug this failing workflow."), .deep)
    }
}
