import Foundation

struct VyronBackgroundConversationRun {
    let response: VyronResponseIdentity
    let balanceConnectionID: UUID?
    let route: VyronForegroundRunRoute
    var isDeveloping: Bool
}
