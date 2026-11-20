import Foundation
import VyronModelDomain

struct VyronAutoLocalConfiguration {
    let provider: any ModelProvider
    let models: [LocalModel]
    let profiles: [ModelConnectionProfile]
    let revision: UUID
}
