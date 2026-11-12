import Foundation
import VyronCore

extension AppModel {
    func executeOfficeTool(
        _ call: DevelopmentToolCall,
        tools: VyronOfficeTools
    ) async throws -> DevelopmentExternalResult {
        guard let definition = VyronOfficeTools.definitions.first(where: { $0.name == call.function.name }) else {
            throw DevelopmentAgentError.invalidTool(VyronOfficeText.unknownOperation)
        }
        if !definition.isReadOnly {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let arguments = String(decoding: try encoder.encode(call.function.arguments), as: UTF8.self)
            // Reuse the existing cancellable native tool review for local output creation.
            appNavigation.showScheduledTasks = false
            let approved = await mcpConnections.review(MCPActionReview(
                connectionName: VyronOfficeText.title,
                toolName: definition.name,
                arguments: arguments
            ))
            try Task.checkCancellation()
            guard approved else {
                return DevelopmentExternalResult(text: VyronOfficeText.actionDeclined, isError: true)
            }
        }
        return try await tools.execute(call)
    }
}
