import Foundation
import VyronCore

@MainActor
struct VyronMacWorkRun {
    let session: VyronMacWorkSession
    let screenshots: VyronMacWorkScreenshots

    static var definitions: [DevelopmentExternalTool] {
        VyronMacWorkTools.definitions + VyronMacWorkScreenshots.definitions
    }

    static func handles(_ call: DevelopmentToolCall) -> Bool {
        definitions.contains { $0.name == call.function.name }
    }

    func execute(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        if VyronMacWorkScreenshots.handles(call.function.name) {
            return try await screenshots.execute(call)
        }
        return try await session.execute(call)
    }

    func updateProjectRoot(_ root: URL) throws {
        try session.updateProjectRoot(root)
        screenshots.invalidateSources()
    }
}
