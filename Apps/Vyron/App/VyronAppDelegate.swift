import AppKit

@MainActor
final class VyronAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        guard let model else { return .terminateNow }
        isTerminating = true
        Task { @MainActor in
            await model.shutdownAsync()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
