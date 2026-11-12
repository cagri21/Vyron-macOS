import Foundation

public struct AgentSnapshot: Codable, Sendable, Equatable {
    public let applicationID: String
    public let text: String
    public let capturedAt: Date

    public init(applicationID: String, text: String, capturedAt: Date = Date()) {
        self.applicationID = applicationID
        self.text = text
        self.capturedAt = capturedAt
    }

    public var isFresh: Bool {
        let age = Date().timeIntervalSince(capturedAt)
        return age >= 0 && age < 30
    }

    package var elementIDs: Set<Int> {
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^\s*\[(\d+)\]"#) else { return [] }
        let nsText = text as NSString
        return Set(
            expression.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap {
                Int(nsText.substring(with: $0.range(at: 1)))
            }
        )
    }
}
