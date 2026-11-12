import Foundation
import VyronDevelopment

enum VyronDevelopmentCompletionStatus {
    static func summary(
        mode: ComposerMode,
        changedFiles: Int,
        commands: [CommandResult]
    ) -> String {
        let checks = commands.filter { result in
            let parts = result.command.split(whereSeparator: \.isWhitespace).map(String.init)
            let executable = parts.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            if executable == "swift" { return parts.dropFirst().contains { ["build", "test"].contains($0) } }
            if executable == "swiftc" { return !parts.contains("--version") }
            if executable == "xcodebuild" {
                return !parts.contains { ["-version", "-list", "-showsdks"].contains($0) }
            }
            return executable == "pytest" || result.command.contains("-m unittest")
                || result.command.contains("node --test")
        }
        let checkStatus: String
        if let latest = checks.last {
            checkStatus =
                latest.timedOut
                ? VyronStatusText.latestCheckTimedOut
                : latest.succeeded ? VyronStatusText.latestCheckPassed : VyronStatusText.latestCheckFailed
        } else if let latest = commands.last {
            checkStatus =
                latest.timedOut
                ? VyronStatusText.lastCommandTimedOut
                : latest.succeeded ? VyronStatusText.lastCommandPassed : VyronStatusText.lastCommandFailed
        } else {
            checkStatus = VyronStatusText.checksNotRun
        }
        return VyronStatusText.developmentSummary(
            mode == .plan ? VyronStatusText.planReady : VyronStatusText.finished,
            VyronStatusText.changedFiles(changedFiles),
            checkStatus
        )
    }
}
