import Foundation
import VyronDevelopment

/// Explains the command boundary without treating a denied service connection as a broken host installation.
enum VyronDevelopmentSimulatorDiagnostic {
    private static let guidance = """
    Simulator command limitation: protected project commands cannot contact Apple's Simulator services. \
    This connection failure does not establish a missing runtime or a broken Mac. Do not recommend a restart \
    or runtime reinstall from this evidence alone, and do not retry through an unguarded launcher. If supplied, \
    vyron_mac tools remain available for the user's authorized UI task: open the project in Xcode, inspect its \
    actual controls, use native app menus, and capture its window. Their own macOS permissions and action reviews \
    apply; they do not grant shell or Simulator-service access. Do not conclude that native app tools are \
    unavailable from this command failure. Opening an app alone does not verify this project's build, a device \
    boot, or the project's launch in a simulator; inspect the actual result.
    """

    static func contextualOutput(_ output: String, result: CommandResult) -> String {
        guard result.exitCode != 0, !result.timedOut, isSimulatorCommand(result.command),
            hasConnectionFailure(result.output) else { return output }
        // Prefix the explanation so the existing bounded tool response retains it before long compiler output.
        return guidance + "\n\n" + output
    }

    private static func isSimulatorCommand(_ command: String) -> Bool {
        let arguments = command.split(whereSeparator: \.isWhitespace).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard let program = arguments.first else { return false }
        let name = URL(fileURLWithPath: program).lastPathComponent
        return ["xcodebuild", "simctl"].contains(name)
            || (name == "xcrun" && arguments.dropFirst().contains(where: {
                ["xcodebuild", "simctl"].contains($0)
            }))
    }

    private static func hasConnectionFailure(_ output: String) -> Bool {
        output.lowercased().split(whereSeparator: \.isNewline).contains { line in
            guard line.contains("coresimulatorservice") || line.contains("simdiskimaged") else { return false }
            return [
                "connection became invalid", "connection is invalid", "connection invalidated", "connection refused",
                "connection was refused", "refuses the connection", "unable to connect", "failed to connect",
                "could not connect", "cannot connect", "unavailable", "not available", "permission denied",
                "operation not permitted", "failed to initialize", "cannot subscribe"
            ].contains(where: line.contains)
        }
    }
}
