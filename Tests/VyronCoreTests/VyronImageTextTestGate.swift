actor VyronImageTextTestGate {
    private var isSuspended = false
    private var suspension: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { suspension = $0 }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() {
        suspension?.resume()
        suspension = nil
    }
}
