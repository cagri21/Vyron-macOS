struct VyronOllamaDevelopmentTokenLimits {
    let maximumContext: Int
    let contextOverride: Int?
    let outputOverride: Int?

    init(maximumContext: Int = 32_768, contextOverride: Int? = nil, outputOverride: Int? = nil) {
        self.maximumContext = maximumContext
        self.contextOverride = contextOverride
        self.outputOverride = outputOverride
    }
}
