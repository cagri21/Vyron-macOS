/// Run-scoped guidance consumed only at boundaries between model requests and tools.
public actor VyronSteeringInbox {
    private var pending: [VyronSteeringMessage] = []
    private var isClosed = false

    public init() {}

    /// A closed run refuses updates so the caller can retain them for the next turn.
    @discardableResult
    public func append(_ message: VyronSteeringMessage) -> Bool {
        guard !isClosed else { return false }
        pending.append(message)
        return true
    }

    /// Closing an empty inbox and checking for late updates form one atomic operation.
    public func drain(finishingIfEmpty: Bool = false) -> [VyronSteeringMessage] {
        if pending.isEmpty, finishingIfEmpty { isClosed = true }
        let messages = pending
        pending.removeAll()
        return messages
    }

    /// The run owner also closes the inbox when a run stops or fails.
    public func close() {
        isClosed = true
    }
}
