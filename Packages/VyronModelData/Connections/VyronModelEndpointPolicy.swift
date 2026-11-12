enum VyronModelEndpointPolicy {
    static let maximumEndpointCharacters = 2_048
    static let maximumModelIDBytes = 512
    static let validPorts = 1...65_535
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
    static let localOllamaHosts: Set<String> = ["localhost", "127.0.0.1"]
    static let secureScheme = "https"
    static let insecureScheme = "http"
    static let compatibleBasePath = "/v1"
    static let ollamaAPIPath = "/api"
}
