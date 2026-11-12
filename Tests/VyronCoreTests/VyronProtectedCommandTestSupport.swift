import Foundation
import XCTest
import VyronDevelopment

enum VyronProtectedCommandTestSupport {
    static func requireExecutionAvailable(_ command: CommandResult) throws {
        let output = command.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.exitCode == 71, !command.timedOut,
            output == "sandbox-exec: sandbox_apply: Operation not permitted" {
            throw XCTSkip(
                "BLOCKED: macOS refused the nested execution protection required by this command: " + output
            )
        }
    }
}
