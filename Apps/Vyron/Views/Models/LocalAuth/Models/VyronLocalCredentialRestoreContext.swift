import Foundation

struct VyronLocalCredentialRestoreContext {
    let activeConnectionID: UUID?
    let connectionRevision: UUID
    let mutations: [UUID: UUID]
}
