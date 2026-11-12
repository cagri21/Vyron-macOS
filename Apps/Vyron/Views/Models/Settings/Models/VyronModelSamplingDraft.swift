import VyronCore

struct VyronModelSamplingDraft: Equatable {
    var temperature: String
    var topP: String

    init(_ settings: ModelSettings) {
        temperature = settings.temperature.map { String($0) } ?? ""
        topP = settings.topP.map { String($0) } ?? ""
    }
}
