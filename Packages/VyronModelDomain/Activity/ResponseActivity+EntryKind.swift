extension ResponseActivity.Entry {
    public enum Kind: String, Codable, Sendable {
        case status, explanation, tool
    }
}
