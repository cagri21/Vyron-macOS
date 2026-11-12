import VyronDevelopment

enum VyronDevelopmentFileOperationOutput {
    static func summary(_ result: VyronProjectFileOperationResult) -> String {
        switch result.kind {
        case .move:
            "Moved " + result.sourcePath + " → " + (result.destinationPath ?? "")
        case .rename:
            "Renamed " + result.sourcePath + " → " + (result.destinationPath ?? "")
        case .trash:
            "Moved " + result.sourcePath + " to Trash. Restore it using Finder’s Trash if needed."
        }
    }
}
