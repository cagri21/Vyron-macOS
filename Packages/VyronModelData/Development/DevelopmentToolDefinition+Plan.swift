import Foundation
import VyronModelDomain

extension DevelopmentToolDefinition {
    static var plan: DevelopmentToolDefinition {
        let tool = VyronDevelopmentPlanToolSchema.definition
        return .init(
            function: .init(
                name: tool.name,
                description: tool.description,
                parameters: .init(schema: tool.inputSchema)
            )
        )
    }

    static var resume: DevelopmentToolDefinition {
        let tool = VyronDevelopmentResumeToolSchema.definition
        return .init(
            function: .init(
                name: tool.name,
                description: tool.description,
                parameters: .init(schema: tool.inputSchema)
            )
        )
    }
}
