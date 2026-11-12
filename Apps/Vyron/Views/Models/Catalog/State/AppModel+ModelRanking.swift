import VyronCore

extension AppModel {
    var modelRanking: VyronModelRankingPresentation {
        let rankings =
            modelSelection.isBuiltinConnection
            ? AgentModelRouter.rankedCodingModels(
                from: modelSelection.models,
                selectedModel: modelSelection.selectedModel,
                effort: composer.effort
            ) : []
        return VyronModelRankingPresentation(
            models: modelSelection.models,
            rankings: rankings,
            isBuiltinConnection: modelSelection.isBuiltinConnection
        )
    }
}
