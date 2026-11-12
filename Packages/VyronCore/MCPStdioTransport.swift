import Foundation
import Darwin

/// Owns one configured subprocess. No shell interpolation is used. Mutable state is lock protected;
/// subprocess I/O runs off the UI executor, and every pending request has a deadline.
final class MCPStdioTransport: @unchecked Sendable {
    typealias Object = [String: DevelopmentJSONValue]
    private struct Pending {
        let continuation: CheckedContinuation<Object, any Error>
        let deadline: Task<Void, Never>
    }
    private let lock = NSLock()
    private var processID: pid_t = 0
    private var exitSource: DispatchSourceProcess?
    private let input = Pipe()
    private let output = Pipe()
    private let writeQueue = DispatchQueue(label: "com.vyron.mcp.stdin")
    private let timeout: TimeInterval
    private var pending: [String: Pending] = [:]
    private var buffer = Data()
    private var closed = false
    private let maximumBytes = 4_194_304

    init(profile: MCPConnectionProfile, secrets: MCPConnectionSecrets, timeout: TimeInterval) throws {
        self.timeout = timeout
        var environment: [String: String] = [:]
        let inherited = ProcessInfo.processInfo.environment
        for key in ["HOME", "TMPDIR", "LANG", "LC_ALL", "USER", "LOGNAME"] {
            environment[key] = inherited[key]
        }
        environment["PATH"] = inherited["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        // GUI applications often start with a minimal PATH; make installed developer tools discoverable.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + environment["PATH"]!
        environment.merge(secrets.environment) { _, configured in configured }
        let executable: String
        if profile.command.hasPrefix("/") {
            executable = profile.command
        } else {
            let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter {
                $0.hasPrefix("/")
            }
            guard
                let resolved = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(profile.command).path })
                    .first(where: FileManager.default.isExecutableFile(atPath:))
            else {
                throw MCPError.configuration(
                    "The MCP server executable was not found. Enter its absolute path or install it first."
                )
            }
            executable = resolved
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw MCPError.configuration("The MCP server executable does not exist or cannot be run.")
        }
        // A separate process group lets cancellation stop launcher descendants (for example npx → node).
        // No shell is involved, and unlisted descriptors are closed in the child.
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw MCPError.transport("Could not prepare the MCP server process.")
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        // Never expose stderr, which can echo credential values supplied to a server.
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw MCPError.transport("Could not prepare the MCP server process.")
        }
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        // libdispatch worker threads may block signals. A server and its descendants
        // must receive cancellation signals regardless of the spawning thread's mask.
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        posix_spawnattr_setsigmask(&attributes, &signalMask)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        sigdelset(&defaultSignals, SIGKILL)
        sigdelset(&defaultSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        let argv = ([executable] + profile.arguments).map { strdup($0) } + [nil]
        let env = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for pointer in argv + env { if let pointer { free(pointer) } } }
        var pid: pid_t = 0
        let status = argv.withUnsafeBufferPointer { args in
            env.withUnsafeBufferPointer { values in
                posix_spawn(&pid, executable, &actions, &attributes, args.baseAddress!, values.baseAddress!)
            }
        }
        guard status == 0, pid > 0 else {
            throw MCPError.transport("The configured MCP server could not be started.")
        }
        processID = pid
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        exitSource = source
        source.setEventHandler { [weak self] in self?.close() }
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            // A single nonblocking read consumes short RPC lines without waiting
            // for the pipe to fill, or blocking teardown during a concurrent close.
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count > 0 { self?.receive(Data(bytes.prefix(count))) }
            else if count == 0 || (errno != EAGAIN && errno != EINTR) { self?.close() }
        }
        source.resume()
    }

    deinit { close() }

    func request(_ data: Data, id: String) async throws -> [String: DevelopmentJSONValue] {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let registered = lock.withLock { () -> Bool in
                    guard !closed, !Task.isCancelled else { return false }
                    let deadline = Task { [weak self, timeout] in
                        do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                        self?.fail(id: id, error: MCPError.timeout)
                        self?.close()
                    }
                    pending[id] = Pending(continuation: continuation, deadline: deadline)
                    return true
                }
                if registered {
                    enqueue(data)
                } else {
                    continuation.resume(throwing: Task.isCancelled ? CancellationError() : MCPError.disconnected)
                }
            }
        } onCancel: { [weak self] in
            self?.fail(id: id, error: CancellationError())
            self?.close()
        }
    }

    func notify(_ data: Data) throws {
        guard !lock.withLock({ closed }) else { throw MCPError.disconnected }
        enqueue(data)
    }

    func close() {
        let stopped: ([Pending], pid_t, DispatchSourceProcess?)? = lock.withLock {
            guard !closed else { return nil }
            closed = true
            let requests = Array(pending.values)
            pending.removeAll(); buffer.removeAll()
            let source = exitSource
            exitSource = nil
            return (requests, processID, source)
        }
        guard let (requests, pid, source) = stopped else { return }
        source?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if pid > 0 {
            _ = Darwin.kill(-pid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                // Keep the group leader unreaped until after the last signal so its PID cannot be reused.
                // This also kills descendants left behind if the launcher has already exited.
                _ = Darwin.kill(-pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            }
        }
        for request in requests {
            request.deadline.cancel()
            request.continuation.resume(throwing: MCPError.disconnected)
        }
    }

    private func enqueue(_ data: Data) {
        writeQueue.async { [weak self] in
            guard let self, !self.lock.withLock({ self.closed }) else { return }
            do {
                var line = data; line.append(10)
                try self.input.fileHandleForWriting.write(contentsOf: line)
            } catch { self.close() }
        }
    }

    private func receive(_ data: Data) {
        let lines: [Data]? = lock.withLock {
            guard !closed, buffer.count + data.count <= maximumBytes else { return nil }
            buffer.append(data)
            var lines: [Data] = []
            while let end = buffer.firstIndex(of: 10) {
                lines.append(Data(buffer[..<end]))
                buffer.removeSubrange(...end)
            }
            return lines
        }
        guard let lines else { close(); return }
        for line in lines where !line.isEmpty {
            guard let message = try? JSONDecoder().decode(Object.self, from: line),
                message["jsonrpc"] == .string("2.0")
            else { close(); return }
            if case .string(let method) = message["method"], let id = message["id"] {
                let result: Object =
                    method == "ping"
                    ? ["jsonrpc": .string("2.0"), "id": id, "result": .object([:])]
                    : [
                        "jsonrpc": .string("2.0"), "id": id,
                        "error": .object([
                            "code": .number(-32601), "message": .string("Client capability not supported")
                        ])
                    ]
                if let response = try? JSONEncoder().encode(result) { enqueue(response) }
            } else if case .string(let id) = message["id"] {
                let request = lock.withLock { pending.removeValue(forKey: id) }
                request?.deadline.cancel()
                request?.continuation.resume(returning: message)
            }
        }
    }

    private func fail(id: String, error: any Error) {
        let request = lock.withLock { pending.removeValue(forKey: id) }
        request?.deadline.cancel()
        request?.continuation.resume(throwing: error)
    }
}
