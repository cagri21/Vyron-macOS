package enum VyronModelPullPhase: Sendable, Equatable {
    case findingModelFiles
    case downloadingModelFiles
    case checkingFiles
    case finishingSetup
    case modelFilesReady
    case downloadingGGUF
    case verifyingGGUF
    case importingModelWeights
}
