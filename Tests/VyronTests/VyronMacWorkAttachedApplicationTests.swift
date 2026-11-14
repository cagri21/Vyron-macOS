import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronMacWorkAttachedApplicationTests: XCTestCase {
    func testAttachedBundleUsesExactURLAfterReviewAndCanBeInspected() async throws {
        let controller = VyronMacWorkTestController()
        let attachment = Self.attachment
        // An attachment claiming a known bundle ID still requires its own launch review.
        let id = VyronMacWorkTestController.app.id
        controller.attachedCatalog[attachment.url.standardizedFileURL] = DesktopApplication(
            id: id, name: "Selected app", bundleIdentifier: id, processIdentifier: 0
        )
        var reviews: [MCPActionReview] = []
        let session = makeSession([attachment], controller: controller, review: {
            reviews.append($0)
            return true
        })

        let list = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.apps, arguments: [:]))
        XCTAssertTrue(list.text.contains("Selected app"))
        XCTAssertFalse(list.text.contains("Calculator"))
        XCTAssertFalse(list.text.contains(attachment.path))
        let searched = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.apps, arguments: ["query": .string(id)]
        ))
        XCTAssertTrue(searched.text.contains("Selected app"))
        XCTAssertFalse(searched.text.contains("Calculator"))

        let opened = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(id)]
        ))
        XCTAssertFalse(opened.isError, opened.text)
        XCTAssertEqual(reviews.count, 1)
        let review = try XCTUnwrap(reviews.first)
        let details = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(review.arguments.utf8))
        XCTAssertEqual(details["attached_application_path"], .string(attachment.path))
        XCTAssertTrue(controller.launchedIDs.isEmpty)
        XCTAssertEqual(controller.launchedApplicationURLs, [attachment.url.standardizedFileURL])
        XCTAssertFalse(opened.text.contains(attachment.path))

        let inspected = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.inspect, arguments: ["application_id": .string(id)]
        ))
        XCTAssertFalse(inspected.isError, inspected.text)
        XCTAssertEqual(session.snapshots[id]?.application.processIdentifier, 43)
    }

    func testTwoDistinctAttachmentsWithTheSameBundleIDCannotUseTheGeneralCatalog() async throws {
        let controller = VyronMacWorkTestController()
        let attachment = Self.attachment
        let other = VyronApplicationAttachment(name: "Second.app", path: "/tmp/Second.app")
        let app = VyronMacWorkTestController.app
        controller.attachedCatalog[attachment.url.standardizedFileURL] = app
        controller.attachedCatalog[other.url.standardizedFileURL] = app
        let session = makeSession([attachment, other], controller: controller, review: { _ in
            XCTFail("An ambiguous app should not reach review")
            return true
        })

        let list = try await session.execute(DevelopmentToolCall(name: VyronMacWorkTools.apps, arguments: [:]))
        XCTAssertFalse(list.text.contains(app.id))
        let opened = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(app.id)]
        ))
        XCTAssertTrue(opened.isError)
        XCTAssertTrue(controller.launchedIDs.isEmpty)
        XCTAssertTrue(controller.launchedApplicationURLs.isEmpty)
    }

    func testFocusOfAnAttachedAppThatQuitsReviewsAndOpensOnlyTheAttachedCopy() async throws {
        let controller = VyronMacWorkTestController()
        let attachment = Self.attachment
        let url = attachment.url.standardizedFileURL
        let id = VyronMacWorkTestController.app.id
        let running = DesktopApplication(id: id, name: "Selected app", bundleIdentifier: id, processIdentifier: 43)
        let stopped = DesktopApplication(id: id, name: "Selected app", bundleIdentifier: id, processIdentifier: 0)
        controller.attachedCatalog[url] = running
        controller.onActivate = { [weak controller] in
            controller?.attachedCatalog[url] = stopped
            throw MacControlError.applicationUnavailable
        }
        var reviews: [MCPActionReview] = []
        let session = makeSession([attachment], controller: controller, review: {
            reviews.append($0)
            return true
        })

        let opened = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(id)]
        ))

        XCTAssertFalse(opened.isError, opened.text)
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(controller.launchedApplicationURLs, [url])
        XCTAssertTrue(controller.launchedIDs.isEmpty)
        let review = try XCTUnwrap(reviews.first)
        let details = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(review.arguments.utf8))
        XCTAssertEqual(details["attached_application_path"], .string(url.path))
    }

    private static var attachment: VyronApplicationAttachment {
        VyronApplicationAttachment(name: "Selected.app", path: "/tmp/Selected.app")
    }

    private func makeSession(
        _ attachments: [VyronApplicationAttachment],
        controller: VyronMacWorkTestController,
        review: @escaping @MainActor (MCPActionReview) async -> Bool
    ) -> VyronMacWorkSession {
        VyronMacWorkSession(
            context: VyronMacWorkContext(
                goal: "Open the attached app", projectRoot: nil, allowsActions: true, attachedApplications: attachments
            ),
            dependencies: VyronMacWorkDependencies(controller: controller, validateCurrent: {}, review: review)
        )
    }
}
