import Darwin
import Foundation

final class CommandState: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var stopped = false
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func started(_ value: pid_t) {
        lock.withLock {
            pid = value
            if cancelled { _ = Darwin.kill(-pid, SIGKILL) }
        }
    }
    func cancel() {
        lock.withLock {
            cancelled = true
            if pid > 0, !stopped { _ = Darwin.kill(-pid, SIGKILL) }
        }
    }
    func kill() { lock.withLock { if pid > 0, !stopped { _ = Darwin.kill(-pid, SIGKILL) } } }
    func complete() { lock.withLock { stopped = true } }
}
