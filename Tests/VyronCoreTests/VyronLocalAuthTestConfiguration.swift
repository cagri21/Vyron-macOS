import Foundation
import os
@testable import VyronCore

final class VyronLocalAuthTestConfiguration: VyronLocalAuthConfigurationStoring {
    private let configuration: VyronLocalAuthConfiguration?
    private let token: Data
    private let removals = OSAllocatedUnfairLock(initialState: Set<UUID>())

    init(configured: Bool = true, token: Data = Data(repeating: 7, count: 32)) throws {
        configuration = configured ? try VyronLocalAuthConfiguration() : nil
        self.token = token
    }

    func load() throws -> VyronLocalAuthConfiguration? { configuration }
    func bootstrapToken() throws -> Data? { token }
    func pendingRemovals() throws -> [UUID] { removals.withLock { Array($0) } }
    func recordRemoval(_ connectionID: UUID) throws { removals.withLock { $0.insert(connectionID) } }
    func completeRemoval(_ connectionID: UUID) throws { removals.withLock { $0.remove(connectionID) } }
}
