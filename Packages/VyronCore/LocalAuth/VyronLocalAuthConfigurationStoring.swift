import Foundation

public protocol VyronLocalAuthConfigurationStoring: Sendable {
    func load() throws -> VyronLocalAuthConfiguration?
    func bootstrapToken() throws -> Data?
    func pendingRemovals() throws -> [UUID]
    func recordRemoval(_ connectionID: UUID) throws
    func completeRemoval(_ connectionID: UUID) throws
}
