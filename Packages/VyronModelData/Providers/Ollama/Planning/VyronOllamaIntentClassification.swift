struct VyronOllamaIntentClassification {
    let latestText: String
    let messages: [ControlPlanningRequest.Message]
    let contextTokens: Int
}
