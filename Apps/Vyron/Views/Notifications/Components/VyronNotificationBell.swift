import SwiftUI

struct VyronNotificationBell: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        let _ = localizationLocale
        Button { isPresented.toggle() } label: {
            Image(systemName: VyronSymbols.notifications)
                .font(VyronNotificationStyle.bell)
                .foregroundStyle(palette.text)
                .frame(width: VyronNotificationStyle.bellSize, height: VyronNotificationStyle.bellSize)
                .background(isPresented ? palette.selection : Color.clear, in: RoundedRectangle(
                    cornerRadius: VyronNotificationStyle.bellRadius
                ))
                .overlay(RoundedRectangle(cornerRadius: VyronNotificationStyle.bellRadius).stroke(
                    isPresented ? palette.controlAccent : Color.clear,
                    lineWidth: VyronNotificationStyle.bellBorderWidth
                ))
                .overlay(alignment: .topTrailing) {
                    if model.unreadNotificationCount > 0 {
                        Circle().fill(palette.controlAccent)
                            .frame(
                                width: VyronNotificationStyle.bellUnreadSize,
                                height: VyronNotificationStyle.bellUnreadSize
                            )
                            .overlay(Circle().stroke(
                                palette.surface,
                                lineWidth: VyronNotificationStyle.unreadBorderWidth
                            ))
                            .padding(VyronNotificationStyle.bellUnreadInset)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: VyronNotificationStyle.bellRadius))
        }
        .buttonStyle(.plain)
        .help(VyronNotificationText.title)
        .accessibilityLabel(VyronNotificationText.title)
        .accessibilityValue(VyronNotificationText.unreadCount(model.unreadNotificationCount))
        .accessibilityAddTraits(isPresented ? .isSelected : [])
    }
}
