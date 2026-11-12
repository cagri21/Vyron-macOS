import Foundation
import XCTest

final class VyronWorkspaceBrowserConfigurationTests: XCTestCase {
    func testHTTPExceptionIsLimitedToWebContent() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: project.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let transportSecurity = try XCTUnwrap(plist["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(transportSecurity["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
        XCTAssertNotEqual(transportSecurity["NSAllowsArbitraryLoads"] as? Bool, true)
    }
}
