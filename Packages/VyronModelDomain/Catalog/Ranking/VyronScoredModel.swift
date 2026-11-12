/// A raw local Auto-selection priority, not a benchmark or a normalized model-quality score.
public struct VyronScoredModel: Identifiable, Equatable, Sendable {
    public var id: String { model.id }
    public let model: LocalModel
    public let score: Double

    public init(model: LocalModel, score: Double) {
        self.model = model
        self.score = score
    }
}
