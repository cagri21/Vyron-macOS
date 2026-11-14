struct VyronUnifiedDiffLine: Sendable {
    let kind: VyronUnifiedDiffLineKind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String

    var unifiedText: String {
        switch kind {
        case .added: "+" + text
        case .removed: "-" + text
        case .context: " " + text
        case .hunk, .noNewline: text
        }
    }
}
