import Foundation

/// URLSession and selection callbacks share this fixture. Its lock protects the catalog and request history.
final class VyronModelPrecisionTransport: @unchecked Sendable {
    static let original = "qwen3.8:27b"
    static let alias = "qwen3.8:latest"
    static let replacement = "qwen3.8:27b-q8_0"

    private let lock = NSLock()
    private let failPull: Bool
    private let failProbe: Bool
    private let holdPull: Bool
    private var installedTags: Set<String>
    private var events: [String] = []

    init(
        replacementInstalled: Bool = false,
        failPull: Bool = false,
        failProbe: Bool = false,
        holdPull: Bool = false
    ) {
        self.failPull = failPull
        self.failProbe = failProbe
        self.holdPull = holdPull
        installedTags = [Self.original, Self.alias]
        if replacementInstalled { installedTags.insert(Self.replacement) }
    }

    var operations: [String] { lock.withLock { events } }
    var tags: Set<String> { lock.withLock { installedTags } }

    func recordSelection(_ tag: String) {
        guard tag != Self.original else { return }
        lock.withLock { events.append("select \(tag)") }
    }

    func handle(_ request: URLRequest, reply: (Int, String) -> Void) {
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/api/tags"):
            reply(200, catalog())
        case ("POST", "/api/show"):
            reply(200, #"{"capabilities":["completion","tools"]}"#)
        case ("POST", "/api/chat"):
            guard let tag = modelName(in: request) else { reply(400, "Missing model"); return }
            lock.withLock { events.append("probe \(tag)") }
            if failProbe { reply(500, #"{"error":"Replacement could not load"}"#) }
            else { reply(200, #"{"message":{"content":"OK"},"done":true}"# + "\n") }
        case ("POST", "/api/pull"):
            guard let tag = modelName(in: request) else { reply(400, "Missing model"); return }
            lock.withLock {
                events.append("pull \(tag)")
                if !holdPull && !failPull { installedTags.insert(tag) }
            }
            guard !holdPull else { return }
            if failPull {
                reply(500, #"{"error":"Replacement download failed"}"#)
            } else {
                reply(200, #"{"status":"success"}"# + "\n")
            }
        case ("DELETE", "/api/delete"):
            guard let tag = modelName(in: request) else { reply(400, "Missing model"); return }
            let removed = lock.withLock {
                events.append("delete \(tag)")
                return installedTags.remove(tag) != nil
            }
            reply(removed ? 200 : 404, "")
        default:
            reply(404, #"{"error":"Unexpected test request"}"#)
        }
    }

    private func catalog() -> String {
        let models = tags.sorted().map { tag in
            let isReplacement = tag == Self.replacement
            let digest = String(repeating: isReplacement ? "b" : "a", count: 64)
            let precision = isReplacement ? "Q8_0" : "nvfp4"
            return #"{"name":"\#(tag)","digest":"\#(digest)","size":1024,"details":{"parameter_size":"27.3B","quantization_level":"\#(precision)"},"capabilities":["completion","tools"]}"#
        }
        return #"{"models":[\#(models.joined(separator: ","))]}"#
    }

    private func modelName(in request: URLRequest) -> String? {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            data = body
        } else {
            return nil
        }
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return payload?["model"] as? String
    }
}
