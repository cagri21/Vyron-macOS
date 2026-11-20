import Foundation
import VyronLocalization
import VyronModelDomain

/// Runs one assessment through the caller's local provider and validates its selection before any continuation.
public enum VyronAutoLocalRouter {
    public static func eligibleCandidates(
        _ candidates: [VyronAutoLocalCandidate],
        context: VyronAutoLocalContext
    ) -> [VyronAutoLocalCandidate] {
        boundedCandidates(candidates.filter { isEligible($0, context: context) })
    }

    static var invalidResponse: ModelProviderError {
        .invalidResponse(VyronModelDataText.invalidResponseItem)
    }

    /// Bounds large inventories while retaining both inference locations and caller priority within each location.
    /// Candidates beyond this subset do not participate in this assessment; no model is downloaded or discovered.
    public static func boundedCandidates(_ candidates: [VyronAutoLocalCandidate]) -> [VyronAutoLocalCandidate] {
        let local = candidates.filter { $0.location == .local }
        let connected = candidates.filter { $0.location == .connected }
        var result: [VyronAutoLocalCandidate] = []
        for index in 0..<max(local.count, connected.count) {
            if index < local.count { result.append(local[index]) }
            if result.count == VyronAutoLocalLimits.maximumCandidates { return result }
            if index < connected.count { result.append(connected[index]) }
            if result.count == VyronAutoLocalLimits.maximumCandidates { return result }
        }
        return result
    }

    public static func route(
        using provider: any ModelProvider,
        request: VyronAutoLocalRequest
    ) async throws -> VyronAutoLocalDecision {
        try Task.checkCancellation()
        try VyronLocalModelTag.validate(request.assessor.name)
        guard !request.candidates.isEmpty,
            request.candidates.count <= VyronAutoLocalLimits.maximumCandidates,
            Set(request.candidates.map(\.id)).count == request.candidates.count,
            request.candidates.allSatisfy(validMetadata),
            request.context.messages.contains(where: {
                $0.role == "user" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { throw invalidResponse }

        let candidates = request.candidates.filter { isEligible($0, context: request.context) }
        guard !candidates.isEmpty else { throw invalidResponse }
        let prompt = try VyronAutoLocalPrompt.make(for: request, candidates: candidates)
        let response = try await assess(
            using: provider,
            request: VyronChatInferenceRequest(
                model: request.assessor.name,
                messages: [ChatMessage(role: .user, content: prompt)],
                configuration: VyronChatInferenceConfiguration(
                    systemPrompt: VyronAutoLocalPrompt.system, effort: .quick, purpose: .modelAssessment
                )
            )
        )
        try Task.checkCancellation()
        guard response.utf8.count <= VyronAutoLocalLimits.maximumResponseBytes else { throw invalidResponse }
        let decoded = try decode(response)
        guard let selected = candidates.first(where: { $0.id == decoded.candidateID }) else {
            throw invalidResponse
        }
        let decision = try decoded.decision(for: selected)
        try Task.checkCancellation()
        return decision
    }

    private static func assess(
        using provider: any ModelProvider,
        request: VyronChatInferenceRequest
    ) async throws -> String {
        // A bounded stream monitors byte counts without retaining generated content or introducing shared mutation.
        let (bytes, continuation) = AsyncThrowingStream<Int, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(VyronAutoLocalLimits.maximumResponseBytes)
        )
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                defer { continuation.finish() }
                let response = try await VyronChatInference.response(
                    using: provider, request: request, onToken: { token in
                        guard !token.isEmpty else { return }
                        if case .dropped = continuation.yield(token.utf8.count) {
                            // Every queued event represents at least one byte; a full buffer exceeds the limit.
                            continuation.finish(throwing: invalidResponse)
                        }
                    }
                )
                try Task.checkCancellation()
                return response
            }
            group.addTask {
                var received = 0
                for try await count in bytes {
                    guard count <= VyronAutoLocalLimits.maximumResponseBytes - received else {
                        throw invalidResponse
                    }
                    received += count
                }
                return nil
            }
            defer {
                group.cancelAll()
                continuation.finish()
            }
            var response: String?
            for try await result in group {
                if let result { response = result }
            }
            guard let response else { throw invalidResponse }
            return response
        }
    }

    private static func validMetadata(_ candidate: VyronAutoLocalCandidate) -> Bool {
        guard !candidate.id.isEmpty, candidate.id.utf8.count <= VyronAutoLocalLimits.maximumIdentifierBytes,
            candidate.model.name.utf8.count <= VyronAutoLocalLimits.maximumModelNameBytes,
            (candidate.model.parameterSize?.utf8.count ?? 0) <= VyronAutoLocalLimits.maximumParameterDescriptionBytes,
            (candidate.model.capabilities?.count ?? 0) <= VyronAutoLocalLimits.maximumCapabilityCount,
            candidate.model.capabilities?.allSatisfy({
                $0.utf8.count <= VyronAutoLocalLimits.maximumCapabilityBytes
            }) != false
        else { return false }
        return true
    }

    private static func isEligible(_ candidate: VyronAutoLocalCandidate, context: VyronAutoLocalContext) -> Bool {
        let model = candidate.model
        let name = model.name.lowercased()
        guard !["embed", "bge-", "all-minilm"].contains(where: name.contains) else { return false }
        if candidate.location == .local {
            guard VyronLocalModelTag.isValid(model.name), ModelCatalog.isAutomaticCandidate(model) else { return false }
        } else {
            do { try ModelEndpoint.validateModelID(model.name) } catch { return false }
        }
        let capabilities = Set((model.capabilities ?? []).map { $0.lowercased() })
        if context.requiresTools {
            let localCoding = candidate.location == .local
                && ModelCatalog.codingIncompatibilityReason(for: model) == nil
            let canVerifyTools = candidate.location == .connected
                && capabilities.contains(VyronAutoLocalCapability.pendingTools.rawValue)
            guard capabilities.contains(VyronAutoLocalCapability.tools.rawValue) || localCoding || canVerifyTools else {
                return false
            }
        }
        let needsImages = context.requiresImages || context.messages.contains { $0.images?.isEmpty == false }
        if needsImages, capabilities.isDisjoint(with: ["vision", "image"]) { return false }
        return true
    }

    private static func decode(_ response: String) throws -> VyronAutoLocalResponse {
        do {
            let data = Data(response.utf8)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                Set(object.keys) == ["candidateID", "complexity", "thinkingLevel"]
            else { throw invalidResponse }
            return try JSONDecoder().decode(VyronAutoLocalResponse.self, from: data)
        } catch { throw invalidResponse }
    }
}
