import Foundation

package struct VyronDevelopmentContextBudget: Sendable {
    package let contextTokens: Int
    package let outputTokens: Int
    package let encodedToolBytes: Int?
    package let maximumMessageBytes: Int

    package init(
        contextTokens: Int,
        outputTokens: Int = 512,
        encodedToolBytes: Int? = nil,
        maximumMessageBytes: Int = VyronDevelopmentMessageBudget.standard.maximumBytes
    ) {
        self.contextTokens = contextTokens
        self.outputTokens = outputTokens
        self.encodedToolBytes = encodedToolBytes
        self.maximumMessageBytes = maximumMessageBytes
    }
}
