import Darwin
import Foundation

enum GuardedCommand {
    static func run(
        _ invocation: VyronCommandInvocation,
        state: CommandState,
        onOutput: @escaping @Sendable (String) -> Void
    ) throws -> CommandResult {
        if state.isCancelled { throw CancellationError() }
        let started = ProcessInfo.processInfo.systemUptime
        let launch = try VyronCommandLaunch(invocation)
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw DevelopmentError("Could not create command output storage.") }
        defer { close(descriptors[0]); close(descriptors[1]) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        posix_spawn_file_actions_addclose(&actions, descriptors[1])
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, invocation.directories.project.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, invocation.directories.project.path)
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let cargv = launch.arguments.map { strdup($0) } + [nil]
        let cenv = launch.environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for pointer in cargv + cenv { if let pointer { free(pointer) } } }
        var pid: pid_t = 0
        let error = cargv.withUnsafeBufferPointer { args in
            cenv.withUnsafeBufferPointer { env in
                posix_spawn(&pid, launch.executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard error == 0 else { throw DevelopmentError("The command could not start (error \(error)).") }
        state.started(pid)
        close(descriptors[1]); descriptors[1] = -1
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        var output = Data(), buffer = [UInt8](repeating: 0, count: 8_192)
        var status: Int32 = 0, ended = false, eof = false, timedOut = false, truncated = false
        defer { state.kill(); state.complete() }
        while !ended || !eof {
            if state.isCancelled || ProcessInfo.processInfo.systemUptime - started >= invocation.request.timeout {
                timedOut = !state.isCancelled
                state.kill()
                if !ended { _ = waitpid(pid, &status, 0); ended = true }
                break
            }
            var poller = pollfd(fd: descriptors[0], events: Int16(POLLIN | POLLHUP), revents: 0)
            _ = poll(&poller, 1, 50)
            if poller.revents != 0 {
                let count = read(descriptors[0], &buffer, buffer.count)
                if count > 0 {
                    let room = max(0, 65_536 - output.count)
                    let accepted = min(room, count)
                    if accepted > 0 {
                        let chunk = Data(buffer.prefix(accepted)); output.append(chunk)
                        onOutput(String(decoding: chunk, as: UTF8.self))
                    }
                    truncated = truncated || count > room
                } else if count == 0 {
                    eof = true
                }
            }
            if !ended, waitpid(pid, &status, WNOHANG) == pid { ended = true }
        }
        state.kill(); state.complete()
        if state.isCancelled { throw CancellationError() }
        let exitCode: Int32 = timedOut ? 124 : ((status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F))
        let result = CommandResult(
            id: UUID(),
            command: invocation.request.command,
            exitCode: exitCode,
            output: String(decoding: output, as: UTF8.self),
            timedOut: timedOut,
            truncated: truncated,
            duration: ProcessInfo.processInfo.systemUptime - started
        )
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: invocation.directories.storage.appendingPathComponent("result.json"), options: .atomic)
        }
        return result
    }
}
