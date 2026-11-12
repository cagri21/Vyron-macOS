import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func vyronPlainStyle() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
