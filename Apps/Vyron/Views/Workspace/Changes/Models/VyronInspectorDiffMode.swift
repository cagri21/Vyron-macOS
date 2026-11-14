enum VyronInspectorDiffMode: CaseIterable {
    case diff
    case before
    case after

    var label: String {
        switch self {
        case .diff: VyronAppText.inspectorDiff
        case .before: VyronAppText.inspectorBefore
        case .after: VyronAppText.inspectorAfter
        }
    }
}
