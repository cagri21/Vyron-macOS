import Foundation
import VyronDevelopment

struct VyronUnifiedDiff: Sendable {
    private static let contextLineCount = 3
    private static let maximumComparisonWork = 4_000_000

    private let oldPath: String
    private let newPath: String
    let filename: String
    let lines: [VyronUnifiedDiffLine]
    let addedCount: Int
    let removedCount: Int

    init(change: DevelopmentChange, maximumLineCount: Int? = nil) {
        filename = (change.path as NSString).lastPathComponent
        oldPath = change.before == nil ? "/dev/null" : "a/" + change.path
        newPath = "b/" + change.path
        let old = VyronDiffSourceLine.split(change.before ?? "")
        let new = VyronDiffSourceLine.split(change.after)
        let offsets = Self.changedOffsets(old: old, new: new)
        addedCount = offsets.insertions.count
        removedCount = offsets.removals.count
        if maximumLineCount == 0 || (addedCount == 0 && removedCount == 0) {
            lines = []
        } else {
            let edits = Self.edits(old: old, new: new, offsets: offsets)
            lines = Self.render(edits, maximumLineCount: maximumLineCount)
        }
    }

    var unifiedText: String {
        guard !lines.isEmpty || oldPath == "/dev/null" else { return "" }
        let patchLines = (["--- " + oldPath, "+++ " + newPath] + lines.map(\.unifiedText))
            .joined(separator: "\n") + "\n"
        if oldPath == "/dev/null" && lines.isEmpty {
            return "diff --git a/\(newPath.dropFirst(2)) \(newPath)\nnew file mode 100644\n"
        }
        return patchLines
    }

    private static func changedOffsets(old: [VyronDiffSourceLine], new: [VyronDiffSourceLine]) -> VyronDiffOffsets {
        var start = 0
        var oldEnd = old.count
        var newEnd = new.count
        while start < min(oldEnd, newEnd), old[start] == new[start] { start += 1 }
        while min(oldEnd, newEnd) > start, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let oldRange = start..<oldEnd
        let newRange = start..<newEnd
        if oldRange.isEmpty || newRange.isEmpty {
            return VyronDiffOffsets(removals: Set(oldRange), insertions: Set(newRange))
        }
        // Keep a substantially rewritten file from tying up the reviewer with a quadratic comparison.
        guard oldRange.count <= maximumComparisonWork / newRange.count else {
            return VyronDiffOffsets(removals: Set(oldRange), insertions: Set(newRange))
        }
        let difference = new[newRange].difference(from: old[oldRange])
        return VyronDiffOffsets(
            removals: Set(difference.removals.map { start + $0.offset }),
            insertions: Set(difference.insertions.map { start + $0.offset })
        )
    }

    private static func edits(
        old: [VyronDiffSourceLine],
        new: [VyronDiffSourceLine],
        offsets: VyronDiffOffsets
    ) -> [VyronDiffEdit] {
        var edits: [VyronDiffEdit] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if offsets.removals.contains(oldIndex) {
                edits.append(VyronDiffEdit(
                    line: VyronUnifiedDiffLine(
                        kind: .removed, oldNumber: oldIndex + 1, newNumber: nil, text: old[oldIndex].text
                    ),
                    endsWithNewline: old[oldIndex].endsWithNewline
                ))
                oldIndex += 1
            } else if offsets.insertions.contains(newIndex) {
                edits.append(VyronDiffEdit(
                    line: VyronUnifiedDiffLine(
                        kind: .added, oldNumber: nil, newNumber: newIndex + 1, text: new[newIndex].text
                    ),
                    endsWithNewline: new[newIndex].endsWithNewline
                ))
                newIndex += 1
            } else {
                edits.append(VyronDiffEdit(
                    line: VyronUnifiedDiffLine(
                        kind: .context, oldNumber: oldIndex + 1, newNumber: newIndex + 1, text: old[oldIndex].text
                    ),
                    endsWithNewline: old[oldIndex].endsWithNewline
                ))
                oldIndex += 1
                newIndex += 1
            }
        }
        return edits
    }

    private static func render(_ edits: [VyronDiffEdit], maximumLineCount: Int?) -> [VyronUnifiedDiffLine] {
        var output: [VyronUnifiedDiffLine] = []
        var previousEnd = 0
        var oldOffset = 0
        var newOffset = 0
        for hunk in hunks(edits) {
            let omitted = edits[previousEnd..<hunk.lowerBound]
            oldOffset += omitted.count
            newOffset += omitted.count
            let content = edits[hunk]
            let oldCount = content.count { $0.line.oldNumber != nil }
            let newCount = content.count { $0.line.newNumber != nil }
            let oldStart = oldOffset + (oldCount == 0 ? 0 : 1)
            let newStart = newOffset + (newCount == 0 ? 0 : 1)
            output.append(VyronUnifiedDiffLine(
                kind: .hunk, oldNumber: nil, newNumber: nil,
                text: "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
            ))
            for edit in content {
                if let maximumLineCount, output.count >= maximumLineCount { return Array(output.prefix(maximumLineCount)) }
                output.append(edit.line)
                if !edit.endsWithNewline {
                    output.append(VyronUnifiedDiffLine(
                        kind: .noNewline, oldNumber: nil, newNumber: nil, text: "\\ No newline at end of file"
                    ))
                }
            }
            oldOffset += oldCount
            newOffset += newCount
            previousEnd = hunk.upperBound
        }
        if let maximumLineCount { return Array(output.prefix(maximumLineCount)) }
        return output
    }

    private static func hunks(_ edits: [VyronDiffEdit]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for index in edits.indices where edits[index].line.kind != .context {
            let start = max(0, index - contextLineCount)
            let end = min(edits.count, index + contextLineCount + 1)
            if let last = ranges.last, start <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound..<end
            } else {
                ranges.append(start..<end)
            }
        }
        return ranges
    }
}
