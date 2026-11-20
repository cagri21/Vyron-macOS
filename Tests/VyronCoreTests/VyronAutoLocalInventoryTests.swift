import XCTest
import VyronModelDomain
@testable import VyronModelData

@MainActor
final class VyronAutoLocalInventoryTests: XCTestCase {
    func testLargeInventoriesRetainBothLocationsAndPreserveTheirPriorities() {
        let local = (0..<40).map { candidate("local-\($0)", location: .local) }
        let connected = (0..<40).map { candidate("connected-\($0)", location: .connected) }
        let first = VyronAutoLocalRouter.boundedCandidates(local + connected)
        let regrouped = VyronAutoLocalRouter.boundedCandidates(connected + local)

        XCTAssertEqual(first, regrouped)
        XCTAssertEqual(first.count, VyronAutoLocalLimits.maximumCandidates)
        XCTAssertEqual(first.filter { $0.location == .local }, Array(local.prefix(16)))
        XCTAssertEqual(first.filter { $0.location == .connected }, Array(connected.prefix(16)))
        XCTAssertEqual(first.prefix(4).map(\.id), ["local-0", "connected-0", "local-1", "connected-1"])
    }

    func testUnusedCapacityIsFilledFromTheRemainingLocation() {
        let local = (0..<40).map { candidate("local-\($0)", location: .local) }
        let connected = [candidate("connected-0", location: .connected)]
        let bounded = VyronAutoLocalRouter.boundedCandidates(local + connected)
        XCTAssertEqual(bounded.count, VyronAutoLocalLimits.maximumCandidates)
        XCTAssertEqual(bounded.filter { $0.location == .local }, Array(local.prefix(31)))
        XCTAssertEqual(bounded.filter { $0.location == .connected }, connected)
        XCTAssertEqual(
            VyronAutoLocalRouter.boundedCandidates(local),
            Array(local.prefix(VyronAutoLocalLimits.maximumCandidates))
        )
    }

    func testEmptyAndSmallInventoriesRetainEveryCandidate() {
        XCTAssertTrue(VyronAutoLocalRouter.boundedCandidates([]).isEmpty)
        let local = candidate("preferred-local", location: .local)
        let connected = candidate("preferred-connected", location: .connected)
        XCTAssertEqual(VyronAutoLocalRouter.boundedCandidates([connected, local]), [local, connected])
    }

    func testOnlyCandidatesInTheBoundedAssessmentCanBeSelected() async throws {
        let local = (0..<40).map { candidate("local-\($0)", location: .local) }
        let connected = candidate("connected", location: .connected)
        let scoped = VyronAutoLocalRequest(
            assessor: LocalModel(name: "assessor:latest", size: 1),
            candidates: VyronAutoLocalRouter.boundedCandidates(local + [connected]),
            context: VyronAutoLocalContext(
                messages: [ChatMessage(role: "user", content: "Explain this request.")],
                reference: "", requiresTools: false, requiresImages: false
            ),
            effort: .automatic
        )
        let provider = VyronAutoLocalTestProvider(response:
            #"{"candidateID":"connected","complexity":"complex","thinkingLevel":null}"#
        )
        let decision = try await VyronAutoLocalRouter.route(using: provider, request: scoped)
        XCTAssertEqual(decision.candidateID, "connected")

        let excluded = VyronAutoLocalTestProvider(response:
            #"{"candidateID":"local-39","complexity":"simple","thinkingLevel":null}"#
        )
        do {
            _ = try await VyronAutoLocalRouter.route(using: excluded, request: scoped)
            XCTFail("Candidates outside this assessment cannot be selected")
        } catch let error as ModelProviderError {
            guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testUnverifiedToolsRemainEligibleForNativeValidationWithoutClaimingVerifiedSupport() {
        let profile = VyronResponsesTestSupport.profile()
        let pending = VyronAutoLocalCandidate(
            id: "pending", model: VyronAutoLocalProviderCapabilities.candidateModel(for: profile, tools: .unverified),
            location: .connected, thinkingSupport: .providerDefaultOnly
        )
        let unsupported = VyronAutoLocalCandidate(
            id: "unsupported", model: VyronAutoLocalProviderCapabilities.candidateModel(for: profile, tools: .unavailable),
            location: .connected, thinkingSupport: .providerDefaultOnly
        )
        let context = VyronAutoLocalContext(
            messages: [ChatMessage(role: .user, content: "Inspect the project")],
            reference: "", requiresTools: true, requiresImages: false
        )
        XCTAssertFalse(pending.model.capabilities?.contains("tools") == true)
        XCTAssertEqual(
            VyronAutoLocalRouter.eligibleCandidates([unsupported, pending], context: context).map(\.id), ["pending"]
        )
    }

    private func candidate(_ id: String, location: VyronAutoLocalLocation) -> VyronAutoLocalCandidate {
        VyronAutoLocalCandidate(
            id: id, model: LocalModel(name: "\(id):latest", size: 1, capabilities: ["completion"]),
            location: location, thinkingSupport: .unsupported
        )
    }
}
