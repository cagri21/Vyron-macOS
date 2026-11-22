import Foundation
import VyronModelData
import VyronModelDomain

extension AppModel {
    func autoLocalConfiguration() -> VyronAutoLocalConfiguration? {
        guard modelSelection.isAutoLocalEnabled, let provider = modelSelection.inferenceProvider else { return nil }
        return VyronAutoLocalConfiguration(
            provider: provider,
            models: modelSelection.models,
            profiles: modelSelection.connectionProfiles,
            revision: modelSelection.connectionRevision
        )
    }

    func resolveAutoLocalInference(
        _ configuration: VyronAutoLocalConfiguration,
        context: VyronAutoLocalContext,
        effort: AgentEffort,
        response: VyronResponseIdentity
    ) async throws -> VyronAutoLocalResolution {
        try checkAutoLocalRun(configuration, response: response)
        guard let services = modelSelection.providers.autoLocal,
            let assessor = AgentModelRouter.selectModel(from: configuration.models, effort: .quick) else {
            throw ModelProviderError.invalidSettings(VyronWorkspaceText.autoLocalUnavailable)
        }
        var candidates = VyronAutoLocalRouter.eligibleCandidates(
            autoLocalCandidates(configuration, requiresTools: context.requiresTools), context: context
        )
        guard !candidates.isEmpty else {
            throw ModelProviderError.invalidSettings(VyronWorkspaceText.autoLocalNoSuitableModel)
        }
        for _ in 0..<min(candidates.count, VyronAutoLocalExecutionPolicy.maximumVerifiedCandidates) {
            recordActivity(
                VyronWorkspaceText.autoLocalAssessing,
                detail: assessor.name,
                conversationID: response.conversationID,
                messageID: response.messageID
            )
            let request = VyronAutoLocalRequest(
                assessor: assessor, candidates: candidates, context: context, effort: effort
            )
            let decision = try await services.assess(configuration.provider, request)
            try checkAutoLocalRun(configuration, response: response)
            guard let candidate = candidates.first(where: { $0.id == decision.candidateID }) else {
                throw ModelProviderError.invalidResponse(VyronWorkspaceText.autoLocalInvalidAssessment)
            }
            let selectedEffort = decision.effectiveEffort(for: effort)
            let resolution = try await autoLocalExecution(
                configuration, candidate: candidate, effort: selectedEffort, response: response
            )
            if context.requiresTools, let check = resolution.inference.provider as? any VyronNativeToolChecking {
                recordActivity(
                    VyronAppText.modelFeaturesChecking,
                    detail: candidate.model.name,
                    conversationID: response.conversationID,
                    messageID: response.messageID
                )
                do {
                    try await check.requireNativeToolSupport(for: candidate.model)
                    try checkAutoLocalRun(configuration, response: response)
                    recordAutoLocalToolResult(.verified, candidate: candidate, configuration: configuration)
                } catch ModelProviderError.unsupportedTools {
                    try checkAutoLocalRun(configuration, response: response)
                    recordAutoLocalToolResult(.unsupported, candidate: candidate, configuration: configuration)
                    candidates.removeAll { $0.id == candidate.id }
                    if candidates.isEmpty { throw ModelProviderError.unsupportedTools }
                    continue
                }
            }
            try checkAutoLocalRun(configuration, response: response)
            let connectionID = candidate.location == .local ? nil : UUID(uuidString: candidate.id)
            foregroundRun.setBalanceConnection(connectionID, for: response)
            recordActivity(
                VyronWorkspaceText.autoLocal,
                detail: VyronWorkspaceText.autoLocalSelected(
                    candidate.model.name, VyronEffortPresentation.title(selectedEffort), resolution.location
                ),
                conversationID: response.conversationID,
                messageID: response.messageID
            )
            return resolution
        }
        throw ModelProviderError.unsupportedTools
    }

    func autoLocalCandidates(
        _ configuration: VyronAutoLocalConfiguration,
        requiresTools: Bool
    ) -> [VyronAutoLocalCandidate] {
        let local = configuration.models.filter { model in
            let rejected = modelFeatures.rejectsLocalNativeTools(for: model.name, revision: configuration.revision)
            return ModelCatalog.isAutomaticCandidate(model)
                && (!requiresTools || (!rejected && ModelCatalog.codingIncompatibilityReason(for: model) == nil))
        }.map { model in
            VyronAutoLocalCandidate(
                id: model.name, model: model, location: .local,
                thinkingSupport: modelFeatures.thinkingChecks.last {
                    $0.selection.connection == nil && $0.selection.modelName == model.name
                        && $0.selection.revision == configuration.revision
                }?.support ?? .unverified
            )
        }
        let connected = configuration.profiles.compactMap { profile -> VyronAutoLocalCandidate? in
            guard !profile.selectedModel.isEmpty else { return nil }
            let report = modelFeatureReport(for: profile)
            guard !requiresTools || report[.agent].isEnabled else { return nil }
            let support = profile.kind == .ollama
                ? modelThinkingSupport(for: profile)
                : VyronAutoLocalProviderCapabilities.thinkingSupport(for: profile)
            return VyronAutoLocalCandidate(
                id: profile.id.uuidString,
                model: VyronAutoLocalProviderCapabilities.candidateModel(for: profile, tools: report[.agent].status),
                location: .connected,
                thinkingSupport: support
            )
        }
        return local + connected
    }

    func checkAutoLocalRun(
        _ configuration: VyronAutoLocalConfiguration,
        response: VyronResponseIdentity
    ) throws {
        try Task.checkCancellation()
        guard foregroundRun.owns(response), !isShuttingDown,
            modelSelection.connectionRevision == configuration.revision else { throw CancellationError() }
    }

    static func autoLocalLocation(for profile: ModelConnectionProfile) -> String {
        let host = URL(string: profile.endpoint)?.host?.lowercased() ?? ""
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
            ? VyronStatusText.localServer : VyronStatusText.remoteServer
    }
}
