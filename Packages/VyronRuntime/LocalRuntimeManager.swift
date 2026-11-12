import Foundation

public enum LocalRuntimeError: LocalizedError, Sendable {
    case notInstalled
    case didNotStart

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Ollama is not installed. Install Ollama, then choose Start local engine."
        case .didNotStart:
            "The local engine did not become ready. Check the Ollama log in the app's support folder."
        }
    }
}

/// Owns only the foreground Ollama process started by this app.
/// Project commands never run through this connection or inherit its permissions.
@MainActor
public final class LocalRuntimeManager {
    private var process: Process?
    private var logHandle: FileHandle?

    public init() {}

    public var isOwnedRuntime: Bool { process?.isRunning == true }

    public static var executableURL: URL? {
        [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    public func startIfNeeded() async throws -> Bool {
        let isReady = await engineIsReady()
        try Task.checkCancellation()
        if isReady { return false }
        if process?.isRunning != true {
            guard let executable = Self.executableURL else {
                throw LocalRuntimeError.notInstalled
            }
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("VyronAI", isDirectory: true)
            try FileManager.default.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let logURL = appSupport.appendingPathComponent("engine.log")
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(
                    atPath: logURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            // Bound the runtime log between launches.
            if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size > 2_000_000 {
                try Data().write(to: logURL, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            let engine = Process()
            engine.executableURL = executable
            engine.arguments = ["serve"]
            engine.environment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "TMPDIR": NSTemporaryDirectory(),
                "OLLAMA_HOST": "127.0.0.1:11434",
                "OLLAMA_NO_CLOUD": "1",
                "OLLAMA_CONTEXT_LENGTH": "32768",
                "OLLAMA_MAX_LOADED_MODELS": "1",
                "OLLAMA_NUM_PARALLEL": "1",
                "OLLAMA_FLASH_ATTENTION": "1",
                "OLLAMA_KV_CACHE_TYPE": "q8_0",
                "OLLAMA_KEEP_ALIVE": "5m"
            ]
            engine.standardOutput = handle
            engine.standardError = handle
            do {
                try engine.run()
            } catch {
                try? handle.close()
                throw error
            }
            logHandle = handle
            process = engine
        }
        do {
            for _ in 0..<60 {
                try Task.checkCancellation()
                if await engineIsReady() { return true }
                guard process?.isRunning == true else { break }
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch {
            stopOwnedRuntime()
            throw error
        }
        stopOwnedRuntime()
        throw LocalRuntimeError.didNotStart
    }

    public func stopOwnedRuntime() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func engineIsReady() async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: config, delegate: NoRuntimeRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:11434/api/version")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["version"] is String
            else { return false }
            return true
        } catch {
            return false
        }
    }
}

private final class NoRuntimeRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
