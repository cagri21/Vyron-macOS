struct VyronDiffOffsets {
    let removals: Set<Int>
    let insertions: Set<Int>
}

extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case .remove(let offset, _, _), .insert(let offset, _, _): offset
        }
    }
}
