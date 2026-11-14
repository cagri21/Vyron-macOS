import Foundation
import VyronDevelopment

struct VyronDiffRevision: Equatable {
    let id: UUID
    let path: String
    let before: String?
    let after: String

    init(_ change: DevelopmentChange) {
        id = change.id
        path = change.path
        before = change.before
        after = change.after
    }
}
