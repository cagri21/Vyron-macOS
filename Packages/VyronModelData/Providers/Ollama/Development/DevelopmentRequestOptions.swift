import Foundation
import VyronModelDomain

func developmentRequestOptions(
    messages: [DevelopmentMessage],
    tools: [DevelopmentToolDefinition],
    effort: AgentEffort,
    limits: VyronOllamaDevelopmentTokenLimits = .init()
) throws -> DevelopmentStepRequest.Options {
    let inputBytes =
        try VyronDevelopmentImageContext.estimatedMessageBytes(messages)
        + JSONEncoder().encode(tools).count + 2_048
    let desiredOutput = limits.outputOverride ?? effort.developmentBudget.outputTokens
    let contextLimit = min(limits.maximumContext, limits.contextOverride ?? 32_768)
    let context =
        limits.contextOverride != nil
        ? contextLimit
        : (effort == .quick && inputBytes + desiredOutput <= 16_384 ? min(16_384, contextLimit) : contextLimit)
    let output = min(desiredOutput, context - inputBytes)
    guard output >= 512 else { throw DevelopmentAgentError.contextBudget }
    return .init(num_ctx: context, num_predict: output)
}
