import Foundation

extension VyronSerialActionQueue {
    struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
}
