import Darwin
import Foundation

public enum VyronChromeNativeHost {
    /// Called only by Chrome's foreground stdio host. No listener, shell, or detached job is created.
    public static func run(origin: String, executable: String) throws {
        let extensionID = try VyronChromeNativeOrigin.validate(
            origin: origin, executable: executable, home: FileManager.default.homeDirectoryForCurrentUser
        )
        let root = try VyronChromeBridgeDirectory.open(VyronChromeBridgePolicy.root, create: true)
        let id = UUID()
        let connection = try VyronChromeNativeHostConnection(root: root, id: id, extensionID: extensionID)
        defer {
            do { try VyronChromeBridgeMailbox.remove(root: root, id: id) }
            catch { FileHandle.standardError.write(Data("Vyron Chrome bridge: session cleanup failed.\n".utf8)) }
        }
        signal(SIGPIPE, SIG_IGN)
        var framing = VyronChromeNativeFraming()
        let helloDeadline = Date().addingTimeInterval(10)
        var receivedHello = false
        while true {
            var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&input, 1, 100)
            if ready < 0, errno == EINTR { continue }
            guard ready >= 0, input.revents & Int16(POLLERR | POLLNVAL) == 0 else {
                throw VyronChromeBridgeError.unavailable
            }
            if input.revents & Int16(POLLIN | POLLHUP) != 0 {
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                if count < 0, errno == EINTR { continue }
                guard count >= 0 else { throw VyronChromeBridgeError.unavailable }
                if count == 0 { try framing.finish(); return }
                for message in try framing.append(Data(bytes.prefix(count))) {
                    try connection.accept(message)
                    receivedHello = true
                }
            }
            guard receivedHello || Date() <= helloDeadline else { throw VyronChromeBridgeError.timeout }
            for message in try connection.outgoing() { try write(VyronChromeNativeFraming.frame(message)) }
        }
    }

    private static func write(_ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { throw VyronChromeBridgeError.invalidMessage }
            while offset < bytes.count {
                let count = Darwin.write(STDOUT_FILENO, address.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw VyronChromeBridgeError.unavailable }
                offset += count
            }
        }
    }
}
