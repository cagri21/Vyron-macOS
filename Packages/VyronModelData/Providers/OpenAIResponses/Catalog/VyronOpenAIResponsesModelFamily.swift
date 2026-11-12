import VyronModelDomain

enum VyronOpenAIResponsesModelFamily: String, CaseIterable, Sendable {
    case gpt6Astra = "gpt-6-astra"
    case gpt6Sol = "gpt-6-sol"
    case gpt6Luna = "gpt-6-luna"
    case gpt61Sol = "gpt-6.1-sol"
    case gpt61Terra = "gpt-6.1-terra"
}
