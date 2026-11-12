import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronEffortPresentationTests: XCTestCase {
    func testEffortTitlesUseLocalizedSixLevelNamesWithoutChangingAutomatic() {
        XCTAssertEqual(VyronEffortPresentation.title(.automatic), VyronWorkspaceText.automaticEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.quick), VyronWorkspaceText.lowEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.balanced), VyronWorkspaceText.mediumEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.deep), VyronWorkspaceText.highEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.extraHigh), VyronWorkspaceText.extraHighEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.maximum), VyronWorkspaceText.maxEffort)
        XCTAssertEqual(VyronEffortPresentation.title(.ultra), VyronWorkspaceText.ultraEffort)
    }

    func testSixDistinctManualStopsRoundTripWhileAutomaticKeepsMediumPosition() {
        XCTAssertEqual(VyronEffortPresentation.position(for: .automatic), 1)
        XCTAssertEqual(VyronEffortPresentation.maximumPosition, 5)
        XCTAssertEqual(VyronEffortPresentation.manualEfforts, [.quick, .balanced, .deep, .extraHigh, .maximum, .ultra])
        for (index, effort) in VyronEffortPresentation.manualEfforts.enumerated() {
            XCTAssertEqual(VyronEffortPresentation.position(for: effort), Double(index))
            XCTAssertEqual(
                VyronEffortPresentation.manualEffort(at: VyronEffortPresentation.position(for: effort)), effort
            )
        }
    }

    func testSliderValuesClampAndRoundToTheNearestActualManualEffort() {
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: -100), .quick)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 0), .quick)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 0.49), .quick)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 0.5), .balanced)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 1), .balanced)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 1.49), .balanced)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 1.5), .deep)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 2), .deep)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 2.49), .deep)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 2.5), .extraHigh)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 3.49), .extraHigh)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 3.5), .maximum)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 4.49), .maximum)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 4.5), .ultra)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 5), .ultra)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: 100), .ultra)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: .greatestFiniteMagnitude), .ultra)
        XCTAssertEqual(VyronEffortPresentation.manualEffort(at: -.greatestFiniteMagnitude), .quick)
    }

    func testNonFiniteSliderValuesFallBackToBalancedWithoutSelectingAutomatic() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(VyronEffortPresentation.manualEffort(at: value), .balanced)
        }
        XCTAssertEqual(
            VyronEffortPresentation.manualEffort(at: VyronEffortPresentation.position(for: .automatic)),
            .balanced
        )
    }

    func testKeyboardAndAccessibilityStepsVisitEveryActualLevelAndClampAtEndpoints() {
        let efforts = VyronEffortPresentation.manualEfforts
        for (index, effort) in efforts.enumerated() {
            XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: effort, by: 0), effort)
            XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: effort, by: 1), efforts[min(5, index + 1)])
            XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: effort, by: -1), efforts[max(0, index - 1)])
        }
        XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: .automatic, by: 0), .automatic)
        XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: .automatic, by: -1), .quick)
        XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: .automatic, by: 1), .deep)
        XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: .balanced, by: Int.max), .ultra)
        XCTAssertEqual(VyronEffortPresentation.steppedEffort(from: .maximum, by: Int.min), .quick)
    }

    func testDescriptionsAreLocalizedForEveryManualLevelAndAutomatic() {
        let expected = [
            VyronWorkspaceText.lowEffortDescription, VyronWorkspaceText.mediumEffortDescription,
            VyronWorkspaceText.highEffortDescription, VyronWorkspaceText.extraHighEffortDescription,
            VyronWorkspaceText.maxEffortDescription, VyronWorkspaceText.ultraEffortDescription
        ]
        XCTAssertEqual(VyronEffortPresentation.manualEfforts.map(VyronEffortPresentation.description), expected)
        XCTAssertEqual(VyronEffortPresentation.description(.automatic), VyronWorkspaceText.automaticEffortDescription)
        XCTAssertEqual(Set(expected).count, 6)
        XCTAssertTrue(expected.allSatisfy { !$0.isEmpty })
    }
}
