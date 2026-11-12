import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import VyronCore
@testable import VyronModelData
@testable import VyronDevelopment

@MainActor
final class VyronOfficeToolsTests: XCTestCase {
    func testPDFRenderingWorksWithoutAnyPythonAndPreservesOriginal() async throws {
        let root = try directory()
        let source = try pdf()
        try source.write(to: root.appendingPathComponent("report.pdf"))
        let runtime = VyronOfficeRuntime(configuration: .init(pythonExecutable: "/missing/python3"))
        let tools = VyronOfficeTools(rootURL: root, runtime: runtime)
        let result = try await tools.execute(call("office_render", input: "report.pdf", output: "previews"))
        XCTAssertFalse(result.isError, result.text)
        let imageURL = root.appendingPathComponent("previews/page-0001.png")
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(image, 0, nil))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("report.pdf")), source)
        let again = try await tools.execute(call("office_render", input: "report.pdf", output: "previews"))
        XCTAssertTrue(again.isError)
    }

    func testToolCatalogExposesOnlyStatusToPlan() throws {
        let plan = try DevelopmentToolDefinition.available(mode: .plan, externalTools: VyronOfficeTools.definitions)
        let names = Set(plan.map { $0.function.name })
        XCTAssertTrue(names.contains("office_status"))
        XCTAssertFalse(names.contains("office_convert"))
        XCTAssertFalse(names.contains("office_render"))
        XCTAssertFalse(names.contains("office_recalculate"))
    }

    func testExtremePDFDimensionsFailWithoutIntegerConversionTrap() throws {
        XCTAssertThrowsError(try VyronOfficePDFRenderer.dimensions(for:
            CGRect(x: 0, y: 0, width: 1e-320, height: 1e-320)
        ))
        XCTAssertThrowsError(try VyronOfficePDFRenderer.dimensions(for:
            CGRect(x: 0, y: 0, width: Double.infinity, height: 100)
        ))
        let normal = try VyronOfficePDFRenderer.dimensions(for: CGRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertEqual(normal.width, 1_600)
        XCTAssertEqual(normal.height, 2_400)
    }

    func testConversionUsesStagedSnapshotAndPublishesOnlyConfirmedOutput() async throws {
        let root = try directory()
        let source = Data([0x50, 0x4B, 0, 1, 2])
        try source.write(to: root.appendingPathComponent("report.docx"))
        let runtime = VyronOfficeRuntime(configuration: .init(pythonExecutable: "/usr/bin/python3")) { request in
            XCTAssertEqual(request.arguments.prefix(2), ["-I", "-B"])
            XCTAssertEqual(request.arguments[3], "convert")
            XCTAssertNotEqual(request.directory, root)
            XCTAssertEqual(try Data(contentsOf: request.directory.appendingPathComponent("input.docx")), source)
            let output = request.directory.appendingPathComponent("output", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            try Data("%PDF-local-result".utf8).write(to: output.appendingPathComponent("document.pdf"))
            return try Self.response(#"{"ok":true,"code":"completed","files":["document.pdf"],"warnings":["Missing fonts may change document layout: FixtureFont"]}"#)
        }
        let tools = VyronOfficeTools(rootURL: root, runtime: runtime)
        let result = try await tools.execute(call("office_convert", input: "report.docx", output: "report.pdf"))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("report.pdf")), Data("%PDF-local-result".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("report.docx")), source)
        XCTAssertTrue(result.text.contains("FixtureFont"))
    }

    func testMissingRuntimeIsActionableAndDoesNotPublishFiles() async throws {
        let root = try directory()
        try Data("Workbook".utf8).write(to: root.appendingPathComponent("source.xlsx"))
        let runtime = VyronOfficeRuntime(configuration: .init(pythonExecutable: "/usr/bin/python3")) { _ in
            try Self.response(#"{"ok":false,"code":"missing_office"}"#, exitCode: 1)
        }
        let tools = VyronOfficeTools(rootURL: root, runtime: runtime)
        let result = try await tools.execute(call("office_recalculate", input: "source.xlsx", output: "calculated.xlsx"))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Settings → Plugins → Office processing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("calculated.xlsx").path))
        let status = try await runtime.status()
        XCTAssertFalse(status.isAvailable)
        XCTAssertTrue(status.message.contains("not been prepared"))
    }

    func testUnknownArgumentsAndOutOfRangePDFPagesDoNotCreateOutputs() async throws {
        let root = try directory()
        try pdf().write(to: root.appendingPathComponent("source.pdf"))
        let tools = VyronOfficeTools(rootURL: root, runtime: VyronOfficeRuntime(configuration: .init()))
        let invalid = DevelopmentToolCall(name: "office_render", arguments: [
            "input_path": .string("source.pdf"), "output_path": .string("previews"), "pages": .array([.number(2)])
        ])
        let result = try await tools.execute(invalid)
        XCTAssertTrue(result.isError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("previews").path))
        let malformed = try await tools.execute(DevelopmentToolCall(name: "office_status", arguments: ["extra": .bool(true)]))
        XCTAssertTrue(malformed.isError)
    }

    func testCancellationWhileRuntimeRunsCannotPublishLateOutput() async throws {
        let root = try directory()
        try Data("Document".utf8).write(to: root.appendingPathComponent("source.docx"))
        let started = root.appendingPathComponent("started")
        let runtime = VyronOfficeRuntime(configuration: .init(pythonExecutable: "/usr/bin/python3")) { _ in
            try Data().write(to: started)
            try await Task.sleep(for: .seconds(30))
            return try Self.response(#"{"ok":true,"code":"completed","files":["document.pdf"]}"#)
        }
        let tools = VyronOfficeTools(rootURL: root, runtime: runtime)
        let request = call("office_convert", input: "source.docx", output: "result.pdf")
        let task = Task { try await tools.execute(request) }
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: started.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: started.path))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled processing must not succeed") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation must stay distinct: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("result.pdf").path))
    }

    func testFailureReleasesRuntimeForExplicitSubsequentRequests() async throws {
        let root = try directory()
        try Data("Document".utf8).write(to: root.appendingPathComponent("source.docx"))
        let runtime = VyronOfficeRuntime(configuration: .init(pythonExecutable: "/missing/python3"))
        let tools = VyronOfficeTools(rootURL: root, runtime: runtime)
        let failure = try await tools.execute(call("office_convert", input: "source.docx", output: "result.pdf"))
        XCTAssertTrue(failure.isError)
        let next = try await tools.execute(DevelopmentToolCall(name: "office_status", arguments: [:]))
        XCTAssertFalse(next.isError)
        XCTAssertTrue(next.text.contains("isAvailable"))
        XCTAssertFalse(next.text.contains("still running"))
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOfficeTools-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func call(_ name: String, input: String, output: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: name, arguments: ["input_path": .string(input), "output_path": .string(output)])
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

    private nonisolated static func response(_ output: String, exitCode: Int = 0) throws -> CommandResult {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "command": "Office fixture", "exitCode": exitCode,
            "output": "VYRON_OFFICE_RESULT " + output, "timedOut": false, "truncated": false, "duration": 0
        ])
        return try JSONDecoder().decode(CommandResult.self, from: data)
    }
}
