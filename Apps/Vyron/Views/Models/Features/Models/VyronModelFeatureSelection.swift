import Foundation
import VyronCore

/// A verification belongs to one connection configuration and selection revision, never a model name alone.
struct VyronModelFeatureSelection: Equatable {
    let connection: ModelConnectionProfile?
    let modelName: String
    let revision: UUID
}
