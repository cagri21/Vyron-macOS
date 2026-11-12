extension ControlPlanningRequest {
    struct Options: Encodable {
        let num_ctx: Int
        let num_predict: Int
        let temperature = 0

        init(num_ctx: Int = 32_768, num_predict: Int = 512) {
            self.num_ctx = num_ctx
            self.num_predict = num_predict
        }
    }
}
