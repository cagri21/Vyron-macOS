import Foundation
import VyronLocalization

/// Classifies a message without executing tools or granting permission to act.
public struct AssistantRoute: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case conversation
        case computerTask
        case clarify
    }

    public let mode: Mode
    public let goal: String?
    public let clarification: String?
    public let effort: AgentEffort

    public init(mode: Mode, goal: String? = nil, clarification: String? = nil, effort: AgentEffort = .automatic) {
        self.mode = mode
        self.goal = goal
        self.clarification = clarification
        self.effort = effort
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, goal, clarification, effort
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw IntentRoutingError.invalidRoute
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(Mode.self, forKey: .mode)
        goal = try values.decodeIfPresent(String.self, forKey: .goal)
        clarification = try values.decodeIfPresent(String.self, forKey: .clarification)
        effort = try values.decode(AgentEffort.self, forKey: .effort)
    }

    public func validated(for latestText: String) throws -> AssistantRoute {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= VyronTaskPromptLimits.maximumUTF8Bytes else {
            throw IntentRoutingError.invalidText
        }
        switch mode {
        case .conversation:
            guard goal == nil, clarification == nil else { throw IntentRoutingError.invalidRoute }
            return AssistantRoute(mode: .conversation, effort: Self.conversationEffort(for: text, fallback: effort))
        case .clarify:
            guard goal == nil, let clarification,
                !clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                clarification.count <= VyronIntentRoutingLimits.maximumClarificationCharacters,
                clarification.utf8.count <= VyronIntentRoutingLimits.maximumClarificationUTF8Bytes
            else { throw IntentRoutingError.invalidRoute }
            return self
        case .computerTask:
            let lower = text.lowercased()
            let informationalPrefixes = [
                "how do i ", "how can i ", "how would one ", "how to ", "show me how ", "tell me how ", "what if ",
                "what happens ", "what would ", "explain ", "can i ", "could i ", "is it possible ", "would it ",
                "can you explain ", "can you tell me ", "write swift code", "write a swift function", "write a swiftui",
                "write swiftui", "generate swift", "write a python function", "nasıl "
            ]
            if informationalPrefixes.contains(where: lower.hasPrefix) {
                return AssistantRoute(mode: .conversation, effort: Self.conversationEffort(for: text, fallback: effort))
            }
            let shortReply = lower.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            if ["do it", "do that", "do this", "go ahead", "continue", "proceed", "yes", "ok", "okay", "please do"]
                .contains(shortReply) {
                return AssistantRoute(mode: .clarify, clarification: VyronModelDomainText.routingClarification)
            }
            guard clarification == nil, text.count <= VyronTaskPromptLimits.maximumCharacters,
                goal == nil || (
                    goal!.count <= VyronTaskPromptLimits.maximumCharacters
                        && goal!.utf8.count <= VyronTaskPromptLimits.maximumUTF8Bytes
                )
            else { throw IntentRoutingError.invalidRoute }
            // The classifier cannot expand the action scope by inventing or rewriting a goal.
            return AssistantRoute(mode: .computerTask, goal: text, effort: effort)
        }
    }

    private static func conversationEffort(for text: String, fallback: AgentEffort) -> AgentEffort {
        let lower = text.lowercased()
        if ["debug", "refactor", "troubleshoot", "compiler error", "compilation error", "stack trace", "crash"]
            .contains(where: lower.contains) {
            return .deep
        }
        if [
            "swift", "swiftui", "python", "javascript", "typescript", "write code", "generate code", "function",
            "algorithm", "programming"
        ].contains(where: lower.contains) {
            return .balanced
        }
        return fallback
    }
}
