import Foundation

actor VyronLocalAuthTestGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var paused = false

    func pause() async {
        paused = true
        for observer in observers { observer.resume() }
        observers.removeAll()
        await withCheckedContinuation { waiter = $0 }
    }

    func waitForPause() async {
        if paused { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func resume() { waiter?.resume(); waiter = nil }
}
