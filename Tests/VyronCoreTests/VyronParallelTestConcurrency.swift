actor VyronParallelTestConcurrency {
    private var current = 0
    private var peak = 0

    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
    func maximum() -> Int { peak }
    func active() -> Int { current }
}
