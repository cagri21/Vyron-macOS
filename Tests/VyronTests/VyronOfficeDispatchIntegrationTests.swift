import CoreGraphics
import Foundation
import ImageIO
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronOfficeDispatchIntegrationTests: XCTestCase {
    func testWorkDispatchesApprovedPDFRenderingThroughNativeOfficeCatalog() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronOfficeDispatchTestProvider()
        try await prepare(test, provider: provider, mode: .agent)
        let document = try pdf()
        let source = test.project.appendingPathComponent("report.pdf")
        try document.write(to: source)
        test.model.composer.draft = "Render the first page of report.pdf into a new previews folder using the local Office tool."
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await waitUntil {
            test.model.mcpConnections.pendingReview != nil || !test.model.foregroundRun.isGenerating
        }
        let review = try XCTUnwrap(test.model.mcpConnections.pendingReview, test.model.errorMessage ?? "No native review")
        XCTAssertEqual(review.toolName, "office_render")
        XCTAssertFalse(FileManager.default.fileExists(atPath: test.project.appendingPathComponent("previews").path))

        test.model.mcpConnections.respondToReview(true)
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertNil(test.model.errorMessage)
        XCTAssertNil(test.model.mcpConnections.pendingReview)
        XCTAssertEqual(test.model.messages.last?.content, VyronOfficeDispatchTestProvider.answer)
        XCTAssertEqual(try Data(contentsOf: source), document)
        let output = test.project.appendingPathComponent("previews/page-0001.png")
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let catalogs = await provider.catalogs
        let officeNames = Set(try XCTUnwrap(catalogs.first).filter { $0.name.hasPrefix("office_") }.map(\.name))
        XCTAssertEqual(officeNames, ["office_status", "office_convert", "office_render", "office_recalculate"])
        let results = await provider.officeResults
        XCTAssertEqual(results.count, 1)
        let result = try XCTUnwrap(results.first)
        let envelope = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(result.utf8))
        guard case .string(let outputText) = envelope["output"] else {
            XCTFail("The successful Office result must carry its published output paths.")
            return
        }
        XCTAssertTrue(outputText.contains(output.path))
    }

    func testPlanReceivesOnlyReadOnlyOfficeStatusAndCreatesNoArtifacts() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronOfficeDispatchTestProvider()
        try await prepare(test, provider: provider, mode: .plan)
        test.model.composer.draft = "Explain how to render report.pdf locally without creating any files."
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertNil(test.model.errorMessage)
        XCTAssertNil(test.model.mcpConnections.pendingReview)
        let catalogs = await provider.catalogs
        XCTAssertFalse(catalogs.isEmpty)
        for catalog in catalogs {
            let office = catalog.filter { $0.name.hasPrefix("office_") }
            XCTAssertEqual(office.map(\.name), ["office_status"])
            XCTAssertTrue(office.allSatisfy(\.isReadOnly))
        }
        let modes = await provider.modes
        XCTAssertTrue(modes.allSatisfy { $0 == .plan })
        XCTAssertFalse(FileManager.default.fileExists(atPath: test.project.appendingPathComponent("previews").path))
    }

    private func prepare(
        _ test: VyronFeatureTestHarness,
        provider: VyronOfficeDispatchTestProvider,
        mode: ComposerMode
    ) async throws {
        test.select(test.profile(modelName: "office-dispatch-fixture"), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = mode
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNil(test.model.errorMessage)
    }

    private func pdf() throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var rectangle = CGRect(x: 0, y: 0, width: 200, height: 300)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &rectangle, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.4, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The in-memory Office dispatch pipeline did not finish.")
        throw CancellationError()
    }
}
