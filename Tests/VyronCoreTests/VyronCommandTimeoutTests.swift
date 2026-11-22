import XCTest
@testable import VyronCore

final class VyronCommandTimeoutTests: XCTestCase {
    func testReleaseTimeoutAcceptsTheRuntimeBoundsAndRejectsValuesOutsideThem() throws {
        for seconds in [5, 180, 900] {
            let call = DevelopmentToolCall(name: "run_command", arguments: [
                "command": .string("swift build -c release"), "timeout_seconds": .number(Double(seconds))
            ])
            guard case .command(_, let decoded) = try DevelopmentInvocation.decode(call, commandAccess: .fullAccess) else {
                return XCTFail("Expected a command invocation.")
            }
            XCTAssertEqual(decoded, Double(seconds))
        }
        for seconds in [4, 901] {
            XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "run_command", arguments: [
                "command": .string("swift build"), "timeout_seconds": .number(Double(seconds))
            ]), commandAccess: .fullAccess))
        }
        XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "run_command", arguments: [
            "command": .string("swift build"), "timeout_seconds": .number(181)
        ])))
        let fallback = try DevelopmentInvocation.decode(DevelopmentToolCall(name: "run_command", arguments: [
            "command": .string("swift build")
        ]))
        guard case .command(_, let seconds) = fallback else { return XCTFail("Expected a command invocation.") }
        XCTAssertEqual(seconds, 120)
    }
}
