import VyronCore

struct VyronModelRankingPresentation {
    let scoredModels: [VyronScoredModel]
    let chatHelpers: [LocalModel]
    let otherModels: [LocalModel]

    init(models: [LocalModel], rankings: [VyronScoredModel], isBuiltinConnection: Bool) {
        scoredModels = isBuiltinConnection ? rankings : []
        let scoredNames = Set(scoredModels.map { $0.model.name })
        chatHelpers =
            isBuiltinConnection
            ? models.filter {
                !scoredNames.contains($0.name) && ModelCatalog.descriptor(for: $0.name)?.role == .helper
            } : []
        let helperNames = Set(chatHelpers.map(\.name))
        otherModels = models.filter { !scoredNames.contains($0.name) && !helperNames.contains($0.name) }
    }

    var allModels: [LocalModel] {
        scoredModels.map(\.model) + chatHelpers + otherModels
    }

    func score(for modelName: String) -> Double? {
        scoredModels.first { $0.model.name == modelName }?.score
    }
}
