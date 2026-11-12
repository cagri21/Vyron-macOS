import Foundation

final class VyronSteeringTestLog<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    func append(_ value: Value) {
        lock.withLock { stored.append(value) }
    }

    var values: [Value] {
        lock.withLock { stored }
    }
}
