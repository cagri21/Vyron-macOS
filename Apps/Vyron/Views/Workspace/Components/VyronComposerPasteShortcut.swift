import AppKit
import SwiftUI

struct VyronComposerPasteShortcut: NSViewRepresentable {
    let isEnabled: Bool
    let pasteAttachment: () -> Bool

    func makeNSView(context: Context) -> VyronComposerPasteMonitor {
        VyronComposerPasteMonitor()
    }

    func updateNSView(_ view: VyronComposerPasteMonitor, context: Context) {
        view.setPasteAction(isEnabled ? pasteAttachment : nil)
    }

    static func dismantleNSView(_ view: VyronComposerPasteMonitor, coordinator: Void) {
        view.setPasteAction(nil)
    }
}
