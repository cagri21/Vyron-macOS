import VyronModelData

struct VyronAppModelOverrides {
    var builtinClient = OllamaClient()
    var balances: VyronConnectionBalanceDependencies?
}
