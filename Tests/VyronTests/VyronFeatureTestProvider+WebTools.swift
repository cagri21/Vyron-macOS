import Foundation
import VyronCore
@testable import Vyron

extension VyronFeatureTestProvider {
    // Preserve the existing ModelProvider requirement while advertising native read-only web tools.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        guard externalTools.allSatisfy({ tool in
            VyronWebTools.definitions.contains(tool) || VyronSkillResourceTools.definitions.contains(tool)
                || VyronChromeTools.definitions.contains(tool)
                || VyronOfficeTools.definitions.contains(tool)
                || (tool.name == "parallel_tasks" && tool.isReadOnly)
        }) else { throw ModelProviderError.unsupportedTools }
        return try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}
