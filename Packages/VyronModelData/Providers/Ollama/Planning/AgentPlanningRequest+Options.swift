extension AgentPlanningRequest {
    struct Options: Encodable {
        let num_ctx: Int
        let num_predict: Int
        let temperature = 0
    }
}
