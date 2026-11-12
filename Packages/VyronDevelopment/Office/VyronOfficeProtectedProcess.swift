import Foundation

public enum VyronOfficeProtectedProcess {
    /// Reuses the project runner's network-denied process group and bounded cancellation.
    /// The writable root is an isolated scratch directory, never the selected project.
    public static func run(_ request: VyronOfficeProcessRequest) async throws -> CommandResult {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw DevelopmentError("macOS execution protection is unavailable. Office processing did not start.")
        }
        let state = CommandState()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                try GuardedCommand.run(
                    command: "Local Office processing",
                    executable: request.executable.path,
                    arguments: request.arguments,
                    root: request.directory,
                    storage: request.directory.appendingPathComponent("process", isDirectory: true),
                    timeout: VyronOfficeLimits.timeout,
                    state: state,
                    onOutput: { _ in }
                )
            }.value
        } onCancel: {
            state.cancel()
        }
    }
}
