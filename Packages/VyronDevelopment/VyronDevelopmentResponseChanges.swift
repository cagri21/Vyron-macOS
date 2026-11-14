import Foundation

package struct VyronDevelopmentResponseChanges: Codable, Sendable, Identifiable {
    package var id: String { workspacePath }
    package let workspacePath: String
    package let changes: [DevelopmentChange]
    package var undonePaths: Set<String>?

    package init(workspacePath: String, changes: [DevelopmentChange]) {
        self.workspacePath = workspacePath
        self.changes = changes
    }

    package var remainingChanges: [DevelopmentChange] {
        changes.filter { undonePaths?.contains($0.path) != true }
    }

    package static func merging(first: DevelopmentChange?, latest: DevelopmentChange) -> DevelopmentChange {
        let isContinuous = first?.id == latest.id
            && latest.before?.utf8.elementsEqual(first?.after.utf8 ?? "".utf8) == true
        return DevelopmentChange(
            id: latest.id,
            path: latest.path,
            before: isContinuous ? first?.before : latest.before,
            after: latest.after,
            unifiedDiff: ""
        )
    }
}
