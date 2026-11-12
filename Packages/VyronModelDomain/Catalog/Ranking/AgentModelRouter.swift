import Foundation

/// Selects only among supplied installed local models; never downloads or contacts a provider.
public enum AgentModelRouter {
    public static func selectModel(
        from models: [LocalModel],
        preferredModel: String? = nil,
        effort: AgentEffort
    ) -> LocalModel? {
        orderedModels(from: models, preferredModel: preferredModel, effort: effort).first
    }

    private static func orderedModels(
        from models: [LocalModel],
        preferredModel: String?,
        effort: AgentEffort
    ) -> [LocalModel] {
        let eligible = models.filter { model in
            guard VyronLocalModelTag.isValid(model.name) else { return false }
            guard ModelCatalog.isAutomaticCandidate(model) else { return false }
            let name = model.name.lowercased()
            guard !["embed", "bge-", "all-minilm"].contains(where: name.contains) else { return false }
            if let capabilities = model.capabilities, !capabilities.isEmpty {
                return !Set(capabilities.map { $0.lowercased() }).isDisjoint(with: ["completion", "chat", "tools"])
            }
            return true
        }
        return eligible.sorted { first, second in
            if effort == .quick {
                let firstSize = first.size > 0 ? first.size : Int64.max
                let secondSize = second.size > 0 ? second.size : Int64.max
                if firstSize != secondSize { return firstSize < secondSize }
            } else {
                let firstScore = score(first, preferredModel: preferredModel, effort: effort)
                let secondScore = score(second, preferredModel: preferredModel, effort: effort)
                if firstScore != secondScore { return firstScore > secondScore }
            }
            if (first.name == preferredModel) != (second.name == preferredModel) { return first.name == preferredModel }
            return first.name < second.name
        }
    }

    public static func selectCodingModel(
        from models: [LocalModel],
        selectedModel: String,
        automaticModelSelection: Bool = true,
        effort: AgentEffort = .balanced
    ) throws -> LocalModel {
        try VyronLocalModelTag.validate(selectedModel)
        if !automaticModelSelection {
            guard let selected = models.first(where: { ModelCatalog.sameInstalledName($0.name, selectedModel) }) else {
                throw LocalAIError.modelNotInstalled(selectedModel)
            }
            if let reason = ModelCatalog.codingIncompatibilityReason(for: selected) {
                throw DevelopmentAgentError.unsupportedModel("\(selected.name): \(reason)")
            }
            return selected
        }
        guard
            let selected = rankedCodingModels(
                from: models,
                selectedModel: selectedModel,
                effort: effort
            ).first?.model
        else {
            throw DevelopmentAgentError.noCodingModel
        }
        return selected
    }

    /// Exposes the same local preference points and order used by automatic development selection.
    /// Incompatible, Chat-only, and manual-only models remain outside this automatic ranking.
    public static func rankedCodingModels(
        from models: [LocalModel],
        selectedModel: String,
        effort: AgentEffort
    ) -> [VyronScoredModel] {
        let compatible = models.filter {
            ModelCatalog.codingIncompatibilityReason(for: $0) == nil && ModelCatalog.isAutomaticCandidate($0)
        }
        let qualityEffort: AgentEffort = effort == .quick || effort == .automatic ? .balanced : effort
        return orderedModels(from: compatible, preferredModel: selectedModel, effort: qualityEffort).map { model in
            VyronScoredModel(model: model, score: score(model, preferredModel: selectedModel, effort: qualityEffort))
        }
    }

    private static func score(_ model: LocalModel, preferredModel: String?, effort: AgentEffort) -> Double {
        let gigabytes = Double(max(model.size, 1)) / 1_000_000_000
        let coding =
            ["coder", "codestral", "devstral", "codegemma"].contains(where: model.name.lowercased().contains) ? 3.0 : 0
        let tools = model.capabilities?.contains("tools") == true ? 3.0 : 0
        let preferred = model.name == preferredModel ? 0.5 : 0
        let weight = effort.prioritizesModelQuality ? log1p(gigabytes) : -abs(log1p(gigabytes) - log1p(12))
        let priority =
            ModelCatalog.descriptor(for: model.name).flatMap { $0.role == .coding ? Double($0.automaticPriority) : nil }
            ?? 0
        return priority + coding + tools + preferred + weight
    }
}
