import Foundation

struct VyronUserInputGateState: Sendable {
    var continuation: CheckedContinuation<VyronUserInputResponse, any Error>?
    var result: Result<VyronUserInputResponse, any Error>?
    var worker: Task<Void, Never>?
}
