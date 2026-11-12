import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronMacWorkSessionTests: XCTestCase {
    func testAppListAndKnownLaunchUseNativeControllerWithoutReview() async throws {
        let controller = VyronMacWorkTestController()
        let app = VyronMacWorkTestController.app
        controller.catalog = [DesktopApplication(
            id: app.id, name: app.name, bundleIdentifier: app.bundleIdentifier, processIdentifier: 0
        )]
        controller.running = []
        var reviews = 0
        let session = makeSession(controller, review: { _ in reviews += 1; return false })
        let list = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.apps, arguments: [:]))
        XCTAssertFalse(list.isError)
        XCTAssertTrue(list.text.contains(app.id))
        let opened = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(app.id)]
        ))
        XCTAssertFalse(opened.isError, opened.text)
        XCTAssertEqual(controller.launchedIDs, [app.id])
        XCTAssertEqual(reviews, 0)
    }

    func testPlanRejectsMutationsAndUnexpectedArgumentsBeforeNativeCalls() async throws {
        let controller = VyronMacWorkTestController()
        let context = VyronMacWorkContext(goal: "Inspect Calculator", projectRoot: nil, allowsActions: false)
        let session = VyronMacWorkSession(context: context, dependencies: VyronMacWorkDependencies(
            controller: controller, validateCurrent: {},
            review: { _ in XCTFail("Plan requested a mutation"); return false }
        ))
        let denied = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(VyronMacWorkTestController.app.id)]
        ))
        XCTAssertTrue(denied.isError)
        let extra = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.apps, arguments: ["code": .string("open anything")]
        ))
        XCTAssertTrue(extra.isError)
        XCTAssertTrue(controller.launchedIDs.isEmpty)
        _ = try await inspect(session)
        XCTAssertEqual(controller.inspections, 1)
    }

    func testOwnedSnapshotCanActOnceAndThenRequiresFreshInspection() async throws {
        let controller = VyronMacWorkTestController()
        let frame = CGRect(x: 10, y: 25, width: 60, height: 35)
        controller.targetFrame = frame
        controller.onElementAction = { [weak controller] in controller?.targetFrame = nil }
        var feedback: [VyronComputerActionFeedback] = []
        let session = makeSession(controller, onTargetAction: { target in
            XCTAssertEqual(controller.clickedIDs, [1])
            feedback.append(target)
        })
        let snapshotID = try await inspect(session)
        let click = action(VyronMacWorkTools.click, snapshotID: snapshotID)
        let result = try await session.execute(click)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(controller.clickedIDs, [1])
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.targetFrame, frame)
        XCTAssertEqual(feedback.first?.applicationID, VyronMacWorkTestController.app.id)
        XCTAssertEqual(feedback.first?.title, VyronControlText.actionClick)
        let repeated = try await session.execute(click)
        XCTAssertTrue(repeated.isError)
        XCTAssertEqual(controller.clickedIDs, [1])
        XCTAssertEqual(feedback.count, 1)
    }

    func testReviewedTextInputShowsItsVerifiedTargetAfterMutation() async throws {
        let controller = VyronMacWorkTestController()
        let frame = CGRect(x: 18, y: 40, width: 160, height: 35)
        controller.elementRole = "AXTextField"
        controller.elementTitle = "Value"
        controller.targetFrame = frame
        let text = "42"
        var feedback: [VyronComputerActionFeedback] = []
        let session = makeSession(controller, review: { _ in true }, onTargetAction: { target in
            XCTAssertEqual(controller.typedTexts, [text])
            feedback.append(target)
        })
        let snapshotID = try await inspect(session)
        let typed = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.typeText, arguments: [
            "application_id": .string(VyronMacWorkTestController.app.id),
            "snapshot_id": .string(snapshotID), "element_id": .number(1), "text": .string(text)
        ]))

        XCTAssertFalse(typed.isError, typed.text)
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.targetFrame, frame)
        XCTAssertEqual(feedback.first?.title, VyronControlText.actionType)
    }

    func testActionWithoutUsableGeometryOrSuccessfulMutationDoesNotShowPointer() async throws {
        let controller = VyronMacWorkTestController()
        let session = makeSession(controller, onTargetAction: { _ in
            XCTFail("An action without a successful, locatable mutation showed a pointer")
        })

        let noFrame = try await session.execute(action(VyronMacWorkTools.click, snapshotID: inspect(session)))
        XCTAssertFalse(noFrame.isError, noFrame.text)
        controller.targetFrame = .zero
        let emptyFrame = try await session.execute(action(VyronMacWorkTools.click, snapshotID: inspect(session)))
        XCTAssertFalse(emptyFrame.isError, emptyFrame.text)

        controller.targetFrame = CGRect(x: 10, y: 25, width: 60, height: 35)
        controller.onElementAction = { throw MacControlError.actionFailed("Test mutation failed") }
        let failed = try await session.execute(action(VyronMacWorkTools.click, snapshotID: inspect(session)))
        XCTAssertTrue(failed.isError)
        XCTAssertEqual(controller.clickedIDs, [1, 1])
    }

    func testActionFinishingAfterOwnershipLossDoesNotShowPointer() async throws {
        let controller = VyronMacWorkTestController()
        let response = VyronMacWorkTestResponseState()
        controller.targetFrame = CGRect(x: 10, y: 25, width: 60, height: 35)
        controller.onElementAction = { response.isCurrent = false }
        let session = VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Add in Calculator", projectRoot: nil, allowsActions: true),
            dependencies: VyronMacWorkDependencies(
                controller: controller, validateCurrent: response.validate, review: { _ in false },
                onTargetAction: { _ in XCTFail("An action outside the active response showed a pointer") }
            )
        )
        let snapshotID = try await inspect(session)
        do {
            _ = try await session.execute(action(VyronMacWorkTools.click, snapshotID: snapshotID))
            XCTFail("Expected the response ownership check to stop the action result")
        } catch is CancellationError {
            XCTAssertEqual(controller.clickedIDs, [1])
        }
    }

    func testDeclinedActionCannotBeRepackagedWithANewSnapshot() async throws {
        let controller = VyronMacWorkTestController()
        controller.elementTitle = "Send"
        controller.targetFrame = CGRect(x: 10, y: 25, width: 60, height: 35)
        var reviews = 0
        let session = makeSession(controller, review: { review in
            reviews += 1
            XCTAssertTrue(review.arguments.contains("Send"))
            return false
        }, onTargetAction: { _ in XCTFail("A declined action showed a pointer") })
        let first = try await session.execute(action(VyronMacWorkTools.click, snapshotID: inspect(session)))
        XCTAssertTrue(first.isError)
        let second = try await session.execute(action(VyronMacWorkTools.click, snapshotID: inspect(session)))
        XCTAssertTrue(second.isError)
        XCTAssertEqual(reviews, 1)
        XCTAssertTrue(controller.clickedIDs.isEmpty)
    }

    func testCancelledResponseCannotActAfterReview() async throws {
        let controller = VyronMacWorkTestController()
        controller.elementTitle = "Send"
        let response = VyronMacWorkTestResponseState()
        let session = VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Send a message", projectRoot: nil, allowsActions: true),
            dependencies: VyronMacWorkDependencies(
                controller: controller, validateCurrent: response.validate,
                review: { _ in response.isCurrent = false; return true }
            )
        )
        let snapshotID = try await inspect(session)
        do {
            _ = try await session.execute(action(VyronMacWorkTools.click, snapshotID: snapshotID))
            XCTFail("A stopped response acted after review")
        } catch is CancellationError {
            XCTAssertTrue(controller.clickedIDs.isEmpty)
        }
    }

    func testNativeTargetChangeDuringReviewPreventsMutation() async throws {
        let controller = VyronMacWorkTestController()
        controller.elementTitle = "Send"
        let session = makeSession(controller, review: { _ in controller.elementTitle = "Delete"; return true })
        let snapshotID = try await inspect(session)
        let result = try await session.execute(action(VyronMacWorkTools.click, snapshotID: snapshotID))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(controller.clickedIDs.isEmpty)
    }

    func testRelaunchedApplicationAndExpiredSnapshotCannotReceiveInput() async throws {
        let controller = VyronMacWorkTestController()
        let session = makeSession(controller)
        let snapshotID = try await inspect(session)
        let app = VyronMacWorkTestController.app
        controller.running = [DesktopApplication(
            id: app.id, name: app.name, bundleIdentifier: app.bundleIdentifier, processIdentifier: 99
        )]
        let relaunched = try await session.execute(action(VyronMacWorkTools.click, snapshotID: snapshotID))
        XCTAssertTrue(relaunched.isError)
        controller.running = [app]
        controller.snapshotDate = Date().addingTimeInterval(-31)
        let oldSnapshotID = try await inspect(session)
        let expired = try await session.execute(action(VyronMacWorkTools.click, snapshotID: oldSnapshotID))
        XCTAssertTrue(expired.isError)
        XCTAssertTrue(controller.clickedIDs.isEmpty)
    }

    func testSecureTargetsAndTerminalTypingRemainRefused() async throws {
        let controller = VyronMacWorkTestController()
        controller.elementIsSecure = true
        let session = makeSession(controller, review: { _ in
            XCTFail("A refused secure field requested approval")
            return true
        })
        let snapshotID = try await inspect(session)
        let secure = try await session.execute(action(VyronMacWorkTools.click, snapshotID: snapshotID))
        XCTAssertTrue(secure.isError)
        XCTAssertTrue(controller.clickedIDs.isEmpty)

        let terminal = DesktopApplication(
            id: "com.apple.Terminal", name: "Terminal", bundleIdentifier: "com.apple.Terminal", processIdentifier: 8
        )
        controller.running = [terminal]
        controller.catalog = [terminal]
        controller.elementIsSecure = false
        controller.elementRole = "AXTextField"
        let inspected = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.inspect, arguments: ["application_id": .string(terminal.id)]
        ))
        let payload = try json(inspected)
        let typed = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.typeText, arguments: [
            "application_id": .string(terminal.id),
            "snapshot_id": .string(try XCTUnwrap(payload["snapshot_id"] as? String)),
            "element_id": .number(1), "text": .string("echo forbidden")
        ]))
        XCTAssertTrue(typed.isError)
        XCTAssertTrue(controller.typedTexts.isEmpty)
    }

    func testKeyboardActionRejectsAChangedVisibleState() async throws {
        let controller = VyronMacWorkTestController()
        let session = makeSession(controller)
        let snapshotID = try await inspect(session)
        controller.onActivate = { controller.inspectionText = "A different focused view" }
        let result = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.pressKey, arguments: [
            "application_id": .string(VyronMacWorkTestController.app.id),
            "snapshot_id": .string(snapshotID), "key": .string("tab")
        ]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(controller.keys.isEmpty)
    }

    private func makeSession(
        _ controller: VyronMacWorkTestController,
        review: @escaping @MainActor (MCPActionReview) async -> Bool = { _ in false },
        onTargetAction: @escaping @MainActor (VyronComputerActionFeedback) -> Void = { _ in }
    ) -> VyronMacWorkSession {
        VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Open Calculator and add 1 + 1", projectRoot: nil, allowsActions: true),
            dependencies: VyronMacWorkDependencies(
                controller: controller, validateCurrent: {}, review: review, onTargetAction: onTargetAction
            )
        )
    }

    private func inspect(_ session: VyronMacWorkSession) async throws -> String {
        let result = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.inspect, arguments: ["application_id": .string(VyronMacWorkTestController.app.id)]
        ))
        XCTAssertFalse(result.isError, result.text)
        return try XCTUnwrap(json(result)["snapshot_id"] as? String)
    }

    private func action(_ name: String, snapshotID: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: name, arguments: [
            "application_id": .string(VyronMacWorkTestController.app.id),
            "snapshot_id": .string(snapshotID), "element_id": .number(1)
        ])
    }

    private func json(_ result: DevelopmentExternalResult) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
    }
}
