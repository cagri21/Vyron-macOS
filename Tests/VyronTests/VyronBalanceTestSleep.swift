import Foundation

struct VyronBalanceTestSleep {
    let deadline: Date
    let continuation: CheckedContinuation<Void, any Error>
}
