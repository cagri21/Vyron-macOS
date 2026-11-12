import VyronCore

actor VyronOpenAIUsageTestRecorder {
    private(set) var events: [VyronOpenAIUsageEvent] = []

    func append(_ event: VyronOpenAIUsageEvent) { events.append(event) }
}
