import Foundation

/// A continuation anchor taken from actual user messages in the owning conversation.
public struct VyronDevelopmentContinuationContext: Sendable {
    public let originalGoal: String
    public let priorResponseIDs: [UUID]
    public let guidance: [String]

    public init(originalGoal: String, priorResponseIDs: [UUID], guidance: [String] = []) {
        self.originalGoal = originalGoal
        self.priorResponseIDs = priorResponseIDs
        self.guidance = guidance
    }

    public static func isContinuationRequest(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return [
            "continue", "please continue", "continue please", "go on", "resume", "please resume", "resume please",
            "devam", "devam et", "devam edin", "lütfen devam et", "devam et lütfen",
            "продовжуй", "продовжуйте", "продовжити",
            // Retain recognition of the exact control-message typo already present in legacy chat history.
            "continıe"
        ].contains(normalized)
    }

    func validated() throws -> Self {
        guard VyronDevelopmentTaskText.isValid(
            originalGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumBytes: VyronDevelopmentTaskLimits.maximumGoalBytes
        ), !Self.isContinuationRequest(originalGoal),
            priorResponseIDs.count <= VyronDevelopmentTaskLimits.maximumContinuationResponses,
            guidance.count <= VyronDevelopmentTaskLimits.maximumGuidanceEntries,
            guidance.reduce(0, { $0 + $1.utf8.count }) <= VyronDevelopmentTaskLimits.maximumGuidanceBytes,
            guidance.allSatisfy({
                VyronDevelopmentTaskText.isValid($0, maximumBytes: VyronDevelopmentTaskLimits.maximumGuidanceBytes)
            }) else {
            throw DevelopmentAgentError.invalidTool(
                "Name the original task before continuing; its verified user goal or response history is unavailable."
            )
        }
        return self
    }
}
