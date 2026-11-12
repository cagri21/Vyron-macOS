import VyronDevelopment

enum VyronDevelopmentFileOperationImpact: Sendable, Equatable {
    case complete(VyronProjectFileOperationImpact)
    case legacy(VyronProjectFileOperationPaths)
}
