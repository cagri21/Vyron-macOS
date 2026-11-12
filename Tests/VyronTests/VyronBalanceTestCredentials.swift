import Foundation

@MainActor
final class VyronBalanceTestCredentials {
    private(set) var requests: [UUID] = []
    var value = "fixture-balance-key"
    var fails = false

    func read(_ id: UUID) throws -> String {
        requests.append(id)
        if fails { throw CocoaError(.fileReadNoPermission) }
        return value
    }
}
