import Foundation
import VyronCore
import VyronModelDomain

/// Scripted inference exercises real native tools; it is not a local-model quality benchmark.
actor VyronLargeCodebaseAnalysisProvider: ModelProvider {
    private(set) var requests: [[DevelopmentMessage]] = []
    private(set) var modes: [DevelopmentMode] = []
    private(set) var requestedModels: [String] = []
    private(set) var observedGoalMarkers: Set<String> = []
    private(set) var sawEarlyEvidence = false
    private(set) var sawLateEvidence = false
    private(set) var leakedExcludedEvidence = false
    private var round = 0
    private var taskDocumentRead = false

    func models() async throws -> [LocalModel] { [] }

    // ModelProvider owns these existing transport signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String { #"{"questions":[]}"# }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        LocalModel(name: model, size: 18_000_000_000, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try respond(VyronDevelopmentInferenceRequest(
            model: model, messages: messages,
            configuration: VyronDevelopmentInferenceConfiguration(effort: effort, mode: mode, externalTools: [])
        ))
    }

    private func respond(_ input: VyronDevelopmentInferenceRequest) throws -> DevelopmentStep {
        let messages = input.messages
        requests.append(messages)
        modes.append(input.configuration.mode)
        requestedModels.append(input.model)
        let text = messages.map(\.content).joined(separator: "\n")
        for marker in ["REQUIREMENT_BEGIN", "REQUIREMENT_MIDDLE", "REQUIREMENT_END"] where text.contains(marker) {
            observedGoalMarkers.insert(marker)
        }
        sawEarlyEvidence = sawEarlyEvidence || messages.contains {
            $0.role == "tool" && $0.content.contains("AUDIT_ME_EARLY_RETRY_WITHOUT_CANCELLATION")
                && $0.content.contains("while true") && $0.content.contains("catch")
        }
        sawLateEvidence = sawLateEvidence || messages.contains {
            $0.role == "tool" && $0.content.contains("AUDIT_ME_LATE_UNBOUNDED_HISTORY")
                && $0.content.contains("history.append(entry)")
        }
        leakedExcludedEvidence = leakedExcludedEvidence
            || text.contains("EXCLUDED_FIXTURE_CANARY_NOT_A_REAL_CREDENTIAL")
        if !taskDocumentRead, input.configuration.externalTools.contains(where: { $0.name == "read_task" }),
            let pending = try taskPages(in: messages) {
            return DevelopmentStep(message: DevelopmentMessage(role: "assistant", toolCalls: pending))
        }
        round += 1
        let call: DevelopmentToolCall
        switch round {
        case 1:
            call = DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(300)])
        case 2:
            call = DevelopmentToolCall(name: "search", arguments: ["query": .string("AUDIT_ME"), "limit": .number(40)])
        case 3:
            call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Feature000.swift")])
        case 4:
            call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Feature599.swift")])
        default:
            guard sawEarlyEvidence, sawLateEvidence else {
                throw ModelProviderError.invalidResponse(
                    "The native tool evidence did not contain the audited sources."
                )
            }
            return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: """
            Reviewed two source hotspots using native file evidence. The inventory and search were bounded; \
            this is not an exhaustive review of all 600 files.
            Sources/Feature000.swift:4: add cancellation checks to retry work.
            Sources/Feature599.swift:5: bound retained history to prevent memory growth.
            No project files were changed and no commands were run.
            """))
        }
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", toolCalls: [call]))
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        try respond(VyronDevelopmentInferenceRequest(
            model: model, messages: messages,
            configuration: VyronDevelopmentInferenceConfiguration(
                effort: effort, mode: mode, externalTools: externalTools
            )
        ))
    }

    private func taskPages(in messages: [DevelopmentMessage]) throws -> [DevelopmentToolCall]? {
        guard let result = messages.last(where: { $0.role == "tool" && $0.toolName == "read_task" }) else {
            return [DevelopmentToolCall(name: "read_task", arguments: ["page": .number(0)])]
        }
        guard case .object(let fields) = try JSONDecoder().decode(
            DevelopmentJSONValue.self, from: Data(result.content.utf8)
        ) else { throw ModelProviderError.invalidResponse("Invalid native task page.") }
        if fields["next_page"] == .null {
            taskDocumentRead = true
            return nil
        }
        guard case .number(let next) = fields["next_page"], case .number(let total) = fields["total_pages"] else {
            throw ModelProviderError.invalidResponse("Missing native task page cursor.")
        }
        return (Int(next)..<min(Int(next) + 4, Int(total))).map { index in
            DevelopmentToolCall(name: "read_task", arguments: ["page": .number(Double(index))])
        }
    }
}
