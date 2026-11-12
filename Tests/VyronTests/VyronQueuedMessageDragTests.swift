import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Vyron

final class VyronQueuedMessageDragTests: XCTestCase {
    func testDragTypeIsDeclaredInPackagedAppAndTransfersOnlyStableIdentities() throws {
        let payload = VyronQueuedMessageDrag(conversationID: UUID(), messageID: UUID())
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(VyronQueuedMessageDrag.self, from: data)
        XCTAssertEqual(decoded.conversationID, payload.conversationID)
        XCTAssertEqual(decoded.messageID, payload.messageID)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(Set(values.keys), ["conversationID", "messageID"])

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: manifest, format: nil
        ) as? [String: Any])
        let declarations = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let matches = declarations.filter {
            $0["UTTypeIdentifier"] as? String == VyronQueuedMessageDrag.contentType.identifier
        }
        XCTAssertEqual(matches.count, 1)
        let declaration = try XCTUnwrap(matches.first)
        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], [UTType.data.identifier])
    }
}
