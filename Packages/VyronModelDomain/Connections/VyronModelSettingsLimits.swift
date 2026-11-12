enum VyronModelSettingsLimits {
    static let minimumContextTokens = 2_048
    static let minimumOutputTokens = 1
    static let defaultMaximumContextTokens = 131_072
    static let defaultMaximumOutputTokens = 32_768
    static let temperature = 0.0...2.0
    static let topP = 0.0...1.0
}
