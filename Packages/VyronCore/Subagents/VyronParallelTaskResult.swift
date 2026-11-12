struct VyronParallelTaskResult: Sendable {
    let identity: VyronSubagentIdentity
    let completion: VyronSubagentCompletion
}
