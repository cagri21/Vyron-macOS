import Foundation

enum VyronWorkspaceBrowserReadPolicy {
    static let timeout: Duration = .seconds(18)
    static let sampleInterval: Duration = .milliseconds(250)
    static let sampleCount = 12
    static let stableSampleCount = 5
    static let textLimit = 12_000
    static let titleLimit = 256
    static let excerptLimit = 350
    static let linkScanLimit = 4_096
    static let readableMediaTypes: Set<String> = ["text/html", "application/xhtml+xml", "text/plain"]
    static let initialViewport = CGRect(x: 0, y: 0, width: 1_024, height: 768)

    static func httpsHost(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
            components.port == nil || components.port == 443
        else { return nil }
        return components.host?.lowercased()
    }

    static let visibleContent = #"""
    const visible = element => element?.getClientRects().length
        && getComputedStyle(element).visibility === "visible";
    const main = [...document.querySelectorAll("main, [role='main']")].find(visible);
    const region = main ?? (visible(document.body) ? document.body : null);
    const title = document.title.trim().slice(0, titleLimit);
    const text = region?.innerText?.trim().slice(0, textLimit) ?? "";
    const challenge = visible(document.querySelector("#challenge-form, #cf-challenge-running"))
        || /^(?:just a moment|checking your browser|verify you are human)[.!…\s]*$/i.test(title);
    const signIn = /^(?:sign[ -]?in|log[ -]?in|authentication required)\b/i.test(title)
        && [...document.querySelectorAll("input[type='password']")].some(visible);
    const loading = /^(?:loading|please wait)[.!…\s]*$/i.test(text);
    const state = challenge ? "challenge" : signIn ? "signIn" : "";
    const links = new Set();
    if (text && !loading && !state) {
        const page = new URL(document.URL);
        page.hash = "";
        const anchors = document.links;
        const count = Math.min(anchors.length, linkScanLimit);
        for (let index = 0; index < count; index++) {
            const anchor = anchors[index];
            if (!anchor.href || anchor.href.length > linkURLLimit || anchor.hasAttribute("download")) continue;
            let link;
            try { link = new URL(anchor.href); } catch { continue; }
            if (link.origin !== page.origin || link.username || link.password) continue;
            link.hash = "";
            if (link.href === page.href) continue;
            links.add(link.href);
            if (links.size >= linkLimit) break;
        }
    }
    return {url: document.URL, title, text: loading ? "" : text, state, links: [...links]};
    """#
}
