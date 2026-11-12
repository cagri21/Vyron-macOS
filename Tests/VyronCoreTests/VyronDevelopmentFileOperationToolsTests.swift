import Foundation
import XCTest
@testable import VyronCore
import VyronDevelopment

final class VyronDevelopmentFileOperationToolsTests: XCTestCase {
    func testMoveRenameAndTrashDecodeTypedRequests() throws {
        let move = try VyronDevelopmentFileOperationTools.decode(call("move_item", [
            "source": .string("Nested/Models"), "destination": .string("Models")
        ]))
        guard case .move(let request) = move else { return XCTFail("Expected a move request.") }
        XCTAssertEqual(request.sourcePath, "Nested/Models")
        XCTAssertEqual(request.destinationPath, "Models")

        let rename = try VyronDevelopmentFileOperationTools.decode(call("rename_item", [
            "path": .string("Models/Old.swift"), "new_name": .string("New.swift")
        ]))
        guard case .rename(let renamed) = rename else { return XCTFail("Expected a rename request.") }
        XCTAssertEqual(renamed.path, "Models/Old.swift")
        XCTAssertEqual(renamed.newName, "New.swift")

        let trash = try VyronDevelopmentFileOperationTools.decode(call("trash_item", [
            "path": .string("Empty folder")
        ]))
        guard case .trash(let trashed) = trash else { return XCTFail("Expected a Trash request.") }
        XCTAssertEqual(trashed.path, "Empty folder")
    }

    func testMissingExtraOrWronglyTypedArgumentsAreRejected() {
        let invalid: [DevelopmentToolCall] = [
            call("move_item", ["source": .string("A")]),
            call("move_item", ["source": .string("A"), "destination": .string("B"), "overwrite": .bool(true)]),
            call("rename_item", ["path": .string("A"), "new_name": .number(1)]),
            call("trash_item", ["path": .string("A"), "permanent": .bool(true)]),
            call("trash_item", ["path": .null]),
            call("delete_item", ["path": .string("A")])
        ]
        for request in invalid { XCTAssertThrowsError(try VyronDevelopmentFileOperationTools.decode(request)) }
    }

    func testRootAbsoluteTraversalAndControlPathsAreRejected() {
        for path in ["", "/tmp/A", "~/Desktop/A", ".", "..", "A/../B", "A//B", "A/", "A\0B", "A\nB"] {
            XCTAssertThrowsError(try VyronDevelopmentFileOperationTools.decode(call("trash_item", [
                "path": .string(path)
            ])), path)
        }
        XCTAssertThrowsError(try VyronDevelopmentFileOperationTools.decode(call("move_item", [
            "source": .string("A"), "destination": .string("/tmp/B")
        ])))
        XCTAssertThrowsError(try VyronDevelopmentFileOperationTools.decode(call("trash_item", [
            "path": .string(String(repeating: "A", count: 4_097))
        ])))
    }

    func testRenameRequiresOnlyOneBoundedFilename() {
        for name in ["Nested/New.swift", ".", "..", String(repeating: "A", count: 256)] {
            XCTAssertThrowsError(try VyronDevelopmentFileOperationTools.decode(call("rename_item", [
                "path": .string("Old.swift"), "new_name": .string(name)
            ])))
        }
    }

    func testSchemasExposeOnlyMutatingNativeOperationsAndRejectExtraProperties() {
        let definitions = VyronDevelopmentFileOperationTools.definitions
        XCTAssertEqual(Set(definitions.map(\.name)), ["move_item", "rename_item", "trash_item"])
        for definition in definitions {
            XCTAssertFalse(definition.isReadOnly)
            XCTAssertEqual(definition.inputSchema["additionalProperties"], .bool(false))
            guard case .object(let properties) = definition.inputSchema["properties"],
                case .array(let required) = definition.inputSchema["required"] else {
                return XCTFail("Expected a strict object schema.")
            }
            let requiredNames = required.compactMap { value -> String? in
                guard case .string(let name) = value else { return nil }
                return name
            }
            XCTAssertEqual(requiredNames.count, required.count)
            XCTAssertEqual(Set(requiredNames), Set(properties.keys))
            for property in properties.values {
                guard case .object(let value) = property else { return XCTFail("Expected a string property.") }
                XCTAssertEqual(value["type"], .string("string"))
            }
        }
        XCTAssertFalse(VyronDevelopmentFileOperationTools.handles(call("run_command", [:])))
        XCTAssertTrue(VyronDevelopmentFileOperationTools.handles(call("move_item", [:])))
    }

    private func call(_ name: String, _ arguments: [String: DevelopmentJSONValue]) -> DevelopmentToolCall {
        DevelopmentToolCall(name: name, arguments: arguments)
    }
}
