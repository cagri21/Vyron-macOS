import Foundation

struct VyronBackgroundConversationRun {
    let response: VyronResponseIdentity
    var balanceConnectionID: UUID?
    let route: VyronForegroundRunRoute
    var isDeveloping: Bool
}
