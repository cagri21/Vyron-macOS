/// Verifies native function transport with a data-only request before starting tool-based work.
public protocol VyronNativeToolChecking: Sendable {
    func requireNativeToolSupport(for model: LocalModel) async throws
}
