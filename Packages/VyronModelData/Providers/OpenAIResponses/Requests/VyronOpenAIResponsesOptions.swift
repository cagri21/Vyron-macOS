import Foundation
import VyronModelDomain

struct VyronOpenAIResponsesOptions {
    let generation: VyronOpenAIResponsesGeneration
    let tools: [DevelopmentToolDefinition]
    let forcedTool: String?
    let measuredInputTokens: Int?

    init(
        generation: VyronOpenAIResponsesGeneration,
        tools: [DevelopmentToolDefinition] = [],
        forcedTool: String? = nil,
        measuredInputTokens: Int? = nil
    ) {
        self.generation = generation
        self.tools = tools
        self.forcedTool = forcedTool
        self.measuredInputTokens = measuredInputTokens
    }
}
