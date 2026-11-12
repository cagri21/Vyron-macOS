import Foundation

enum VyronWorkspaceBrowserPolicy {
    static func allows(_ url: URL) -> Bool {
        VyronWorkspaceAddress.isAllowedWebsite(url)
    }

    static func allowsNavigation(_ url: URL, isMainFrame: Bool) -> Bool {
        if allows(url) { return true }
        guard !isMainFrame, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        switch components.scheme?.lowercased() {
        case "about":
            return components.host == nil && components.query == nil
                && ["blank", "srcdoc"].contains(components.path.lowercased())
        case "data":
            return true
        case "blob":
            let origin = String(url.absoluteString.dropFirst("blob:".count))
            if origin.hasPrefix("null/") { return true }
            guard let source = URL(string: origin) else { return false }
            return allows(source)
        default:
            return false
        }
    }
}
