extension ResponseActivity {
    public enum State: String, Codable, Sendable {
        case working, completed, stopped, failed
    }
}
