extension DevelopmentStepRequest {
    struct Options: Encodable {
        let num_ctx: Int; let num_predict: Int; var temperature: Double = 0.1; var top_p: Double? = nil
    }
}
