import Darwin
import Foundation
import VyronAutomation

@main
enum VyronChromeHost {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else { throw VyronChromeBridgeError.invalidOrigin }
            try VyronChromeNativeHost.run(origin: CommandLine.arguments[1], executable: CommandLine.arguments[0])
        } catch {
            // Native messaging stdout contains only framed protocol messages.
            FileHandle.standardError.write(Data("Vyron Chrome bridge could not start or continue safely.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
