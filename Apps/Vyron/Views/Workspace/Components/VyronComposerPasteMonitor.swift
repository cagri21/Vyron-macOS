import AppKit

final class VyronComposerPasteMonitor: NSView {
    private var eventMonitor: Any?
    private var pasteAttachment: (() -> Bool)?

    func setPasteAction(_ action: (() -> Bool)?) {
        pasteAttachment = action
        if action != nil, eventMonitor == nil {
            // The Edit menu can handle Command-V before the SwiftUI text field receives it.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return handlePaste(event)
            }
        } else if action == nil, let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handlePaste(_ event: NSEvent) -> NSEvent? {
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
            event.charactersIgnoringModifiers?.lowercased() == "v",
            let window, window.isKeyWindow, event.window === window,
            (window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true,
            pasteAttachment?() == true
        else { return event }
        return nil
    }
}
