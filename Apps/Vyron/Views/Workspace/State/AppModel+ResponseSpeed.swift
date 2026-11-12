import Foundation
import VyronCore

extension AppModel {
    var responseSpeed: VyronResponseSpeed {
        VyronResponseSpeedPolicy.effectiveSpeed(
            connection: modelSelection.activeConnectionProfile, model: modelSelection.selectedModel
        )
    }

    var supportsFastResponses: Bool {
        VyronResponseSpeedPolicy.supportsFast(
            connection: modelSelection.activeConnectionProfile, model: modelSelection.selectedModel
        )
    }

    var canSelectResponseSpeed: Bool {
        canSelectDevelopmentEffort && modelSelection.activeConnectionProfile.map {
            VyronConnectionBalancePolicy.support(for: $0) == .dashboardOnly
        } == true
    }

    /// The builder is an explicit provider-construction seam; changing speed never sends a test prompt.
    @discardableResult
    func selectResponseSpeed(
        _ speed: VyronResponseSpeed,
        providerBuilder: (@MainActor (ModelConnectionProfile) throws -> any ModelProvider)? = nil
    ) -> Bool {
        guard canSelectResponseSpeed, speed != .fast || supportsFastResponses,
            var profile = modelSelection.activeConnectionProfile,
            let index = modelSelection.connectionProfiles.firstIndex(where: { $0.id == profile.id })
        else { return false }
        guard (profile.settings.responseSpeed ?? .standard) != speed else { return true }
        let previousSelection = modelFeatureSelection(for: profile)
        profile.settings.responseSpeed = speed
        do {
            let provider: any ModelProvider
            if let providerBuilder {
                provider = try providerBuilder(profile)
            } else {
                provider = try modelSelection.makeProvider(for: profile, apiKey: savedAPIKey(for: profile.id))
            }
            var saved = modelSelection.connectionState
            saved.profiles[index] = profile
            try modelSelection.persist(saved)
            cancelModelFeatureVerification()
            modelSelection.replaceConfiguredProvider(provider, profiles: saved.profiles)
            retainConnectionFeatureVerification(from: previousSelection, for: profile)
            modelSelection.connectionError = nil
            return true
        } catch {
            modelSelection.connectionError = error.localizedDescription
            return false
        }
    }
}
