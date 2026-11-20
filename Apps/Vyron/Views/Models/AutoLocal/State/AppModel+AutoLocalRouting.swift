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
        let candidates = VyronAutoLocalRouter.eligibleCandidates(
            autoLocalCandidates(configuration, requiresTools: context.requiresTools), context: context
        )
        guard !candidates.isEmpty else {
            throw ModelProviderError.invalidSettings(VyronWorkspaceText.autoLocalNoSuitableModel)
        }
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
        let provider: any ModelProvider
        let location: String
        let connectionID: UUID?
        if candidate.location == .local {
            let saved = modelSelection.builtinModelSettings
            let settings = VyronAutoLocalThinkingSettings.applying(
                to: saved, support: candidate.thinkingSupport, effort: selectedEffort
            )
            if settings == saved {
                provider = configuration.provider
            } else {
                provider = try modelSelection.providers.builtin(settings)
            }
            location = VyronWorkspaceText.thisMac
            connectionID = nil
        } else {
            guard let profile = configuration.profiles.first(where: { $0.id.uuidString == candidate.id }),
                modelSelection.connectionProfiles.contains(profile) else {
                throw ModelProviderError.invalidSettings(VyronStatusText.connectionUnavailable)
            }
            // Read only the chosen connection's credential, after local assessment has finished.
            var executionProfile = profile
            if profile.kind == .ollama || VyronDeepSeekRoute.matches(profile) {
                executionProfile.settings = VyronAutoLocalThinkingSettings.applying(
                    to: profile.settings, support: candidate.thinkingSupport, effort: selectedEffort
                )
            }
            provider = try await services.makeProvider(executionProfile)
            try checkAutoLocalRun(configuration, response: response)
            guard modelSelection.connectionProfiles.contains(profile) else { throw CancellationError() }
            location = Self.autoLocalLocation(for: profile)
            connectionID = profile.id
        }
        try checkAutoLocalRun(configuration, response: response)
        foregroundRun.setBalanceConnection(connectionID, for: response)
        recordActivity(
            VyronWorkspaceText.autoLocal,
            detail: VyronWorkspaceText.autoLocalSelected(
                candidate.model.name, VyronEffortPresentation.title(selectedEffort), location
            ),
            conversationID: response.conversationID,
            messageID: response.messageID
        )
        return VyronAutoLocalResolution(
            inference: .init(provider: provider, model: candidate.model.name, effort: selectedEffort),
            location: location
        )
    }

    func autoLocalCandidates(
        _ configuration: VyronAutoLocalConfiguration,
        requiresTools: Bool
    ) -> [VyronAutoLocalCandidate] {
        let local = configuration.models.filter { model in
            ModelCatalog.isAutomaticCandidate(model)
                && (!requiresTools || ModelCatalog.codingIncompatibilityReason(for: model) == nil)
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

    private func checkAutoLocalRun(
        _ configuration: VyronAutoLocalConfiguration,
        response: VyronResponseIdentity
    ) throws {
        try Task.checkCancellation()
        guard foregroundRun.owns(response), !isShuttingDown,
            modelSelection.connectionRevision == configuration.revision else { throw CancellationError() }
    }

    private static func autoLocalLocation(for profile: ModelConnectionProfile) -> String {
        let host = URL(string: profile.endpoint)?.host?.lowercased() ?? ""
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
            ? VyronStatusText.localServer : VyronStatusText.remoteServer
    }
}
