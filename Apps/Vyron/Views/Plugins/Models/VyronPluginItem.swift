import Foundation
import VyronCore

/// Maps a saved connection into the information shown by the Plugins page.
struct VyronPluginItem {
    static let documentationURL = URL(string: "https://help.penpot.app/mcp/")
    let profile: MCPConnectionProfile

    var isPenpot: Bool {
        profile.name.compare("Penpot", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    var address: String {
        profile.transport == .http ? profile.endpoint : profile.command
    }

    var transportTitle: String {
        profile.transport == .http ? VyronPluginText.transportHTTP : VyronPluginText.transportStdio
    }

    var permissionTitle: String {
        profile.permission == .readOnly ? VyronPluginText.permissionReadOnly : VyronPluginText.permissionReview
    }

    var canReviewWrites: Bool { profile.permission == .askForWrites }
}
