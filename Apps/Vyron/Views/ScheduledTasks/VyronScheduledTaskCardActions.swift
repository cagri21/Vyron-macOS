import Foundation

struct VyronScheduledTaskCardActions {
    let edit: () -> Void
    let remove: () -> Void
    let openResult: (UUID) -> Void
}
