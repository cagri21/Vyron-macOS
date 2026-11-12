import Foundation
import VyronModelDomain

extension VyronDevelopmentRequestBudget {
    static func messages(
        _ messages: [DevelopmentMessage],
        tools: [DevelopmentToolDefinition],
        budget: VyronDevelopmentContextBudget,
        encodedMessageBytes: ([DevelopmentMessage]) throws -> Int = { try JSONEncoder().encode($0).count }
    ) throws -> [DevelopmentMessage] {
        try self.messages(
            messages,
            budget: budget,
            measureToolBytes: { try JSONEncoder().encode(tools).count },
            encodedMessageBytes: encodedMessageBytes
        )
    }
}
