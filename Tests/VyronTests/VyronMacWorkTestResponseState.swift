import Foundation

@MainActor
final class VyronMacWorkTestResponseState {
    var isCurrent = true

    func validate() throws {
        guard isCurrent else { throw CancellationError() }
    }
}
