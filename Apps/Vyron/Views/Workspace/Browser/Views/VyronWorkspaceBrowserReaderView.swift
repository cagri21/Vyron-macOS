import AppKit
import SwiftUI
import WebKit

struct VyronWorkspaceBrowserReaderView: NSViewRepresentable {
    let reader: VyronWorkspaceBrowserReader

    func makeNSView(context: Context) -> WKWebView { reader.webView }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isEnabled = context.environment.isEnabled
        if !isEnabled, let responder = webView.window?.firstResponder as? NSView,
            responder === webView || responder.isDescendant(of: webView) {
            webView.window?.makeFirstResponder(nil)
        }
        webView.isHidden = !isEnabled
    }
}
