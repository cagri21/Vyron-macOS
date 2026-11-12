import AppKit
import SwiftUI

@MainActor
enum VyronComposerReturnKey {
    static func handle(
        modifiers: EventModifiers,
        editor: (any NSTextInputClient)?,
        submit: () -> Void
    ) -> KeyPress.Result {
        guard editor?.hasMarkedText() != true else { return .ignored }
        let modifiers = modifiers.subtracting(.capsLock)
        if modifiers == .shift {
            guard let editor else { return .ignored }
            editor.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            return .handled
        }
        guard modifiers.isEmpty else { return .ignored }
        submit()
        return .handled
    }
}
