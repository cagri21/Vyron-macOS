import Foundation
import VyronModelData
import VyronModelDomain

extension AppModel {
    func autoLocalExecution(
        _ configuration: VyronAutoLocalConfiguration,
        candidate: VyronAutoLocalCandidate,
        effort selectedEffort: AgentEffort,
        response: VyronResponseIdentity
    ) async throws -> VyronAutoLocalResolution {
        guard let services = modelSelection.providers.autoLocal else {
            throw ModelProviderError.invalidSettings(VyronWorkspaceText.autoLocalUnavailable)
        }
        let provider: any ModelProvider
        let location: String
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
        }
        return VyronAutoLocalResolution(
            inference: .init(provider: provider, model: candidate.model.name, effort: selectedEffort), location: location
        )
    }

    func recordAutoLocalToolResult(
        _ result: VyronNativeToolVerification,
        candidate: VyronAutoLocalCandidate,
        configuration: VyronAutoLocalConfiguration
    ) {
        let connection = candidate.location == .local ? nil
            : configuration.profiles.first { $0.id.uuidString == candidate.id }
        recordModelToolVerification(result, selection: .init(
            connection: connection, modelName: candidate.model.name, revision: configuration.revision
        ))
    }
}
