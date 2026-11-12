import Foundation
import XCTest
@testable import VyronCore
@testable import VyronDevelopment

final class VyronDevelopmentSimulatorDiagnosticTests: XCTestCase {
    func testDeniedSimulatorConnectionsIncludeBoundaryContextAndPreserveRawOutput() {
        for diagnostic in [
            "CoreSimulatorService connection became invalid. Simulator services will no longer be available.",
            "Unable to connect to CoreSimulatorService: Connection refused",
            "simdiskimaged is unavailable: Operation not permitted"
        ] {
            let command = result(diagnostic)
            let contextual = VyronDevelopmentSimulatorDiagnostic.contextualOutput(diagnostic, result: command)

            XCTAssertTrue(contextual.hasPrefix("Simulator command limitation:"), contextual)
            XCTAssertTrue(contextual.contains("does not establish a missing runtime or a broken Mac"), contextual)
            XCTAssertTrue(contextual.contains("do not retry through an unguarded launcher"), contextual)
            XCTAssertTrue(contextual.contains("vyron_mac tools remain available"), contextual)
            XCTAssertTrue(contextual.contains("Do not conclude that native app tools are unavailable"), contextual)
            XCTAssertTrue(contextual.hasSuffix(diagnostic), contextual)
            XCTAssertEqual(command.output, diagnostic)
        }
    }

    func testXcodebuildAndDirectSimctlHaveTheSameBoundaryContext() {
        let diagnostic = "CoreSimulatorService connection became invalid."
        for command in [
            "xcodebuild -project Finator.xcodeproj -sdk iphonesimulator build",
            "'/usr/bin/xcodebuild' -project Finator.xcodeproj build",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl list devices",
            "xcrun --sdk iphonesimulator simctl list devices"
        ] {
            let contextual = VyronDevelopmentSimulatorDiagnostic.contextualOutput(
                diagnostic, result: result(diagnostic, command: command)
            )
            XCTAssertTrue(contextual.hasPrefix("Simulator command limitation:"), command)
        }
    }

    func testSuccessfulCommandsUnrelatedFailuresAndPlainServiceMentionsStayUnchanged() {
        let examples = [
            result("CoreSimulatorService connection became invalid.", exitCode: 0),
            result("CoreSimulatorService connection became invalid.", timedOut: true),
            result("Finator.swift:12: error: cannot find 'balance' in scope", command: "xcodebuild build"),
            result("This documentation describes CoreSimulatorService and simdiskimaged."),
            result("CoreSimulatorService connection became invalid.", command: "python3 documentation.py"),
            result("Connection refused by another service.\nCoreSimulatorService documentation follows.")
        ]
        for command in examples {
            XCTAssertEqual(
                VyronDevelopmentSimulatorDiagnostic.contextualOutput(command.output, result: command), command.output
            )
        }
    }

    func testBoundaryExplanationSurvivesBoundedModelOutput() throws {
        let diagnostic = "CoreSimulatorService connection became invalid.\n"
            + String(repeating: "compiler output\n", count: 2_000)
        let contextual = VyronDevelopmentSimulatorDiagnostic.contextualOutput(diagnostic, result: result(diagnostic))
        let response = DevelopmentAgent.toolResponse(ok: false, output: contextual, maximumBytes: 2_048)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])

        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["truncated"] as? Bool, true)
        let bounded = try XCTUnwrap(payload["output"] as? String)
        XCTAssertTrue(bounded.hasPrefix("Simulator command limitation:"), bounded)
        XCTAssertTrue(bounded.contains("do not retry through an unguarded launcher"), bounded)
    }

    private func result(
        _ output: String,
        command: String = "xcrun simctl list devices booted",
        exitCode: Int32 = 1,
        timedOut: Bool = false
    ) -> CommandResult {
        CommandResult(
            id: UUID(), command: command, exitCode: exitCode, output: output,
            timedOut: timedOut, truncated: false, duration: 0.01
        )
    }
}
