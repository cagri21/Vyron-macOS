enum VyronModelTransferKind: Sendable, Equatable {
    case pull
    case ggufImport
    case precisionReplacement(VyronModelPrecisionChange)
}
