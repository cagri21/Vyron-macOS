extension ControlPlanningRequest {
    struct Message: Encodable {
        let role: String
        let content: String
    }
}
