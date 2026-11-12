import SwiftUI

struct VyronNotificationBell: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        let _ = localizationLocale
        Button { isPresented.toggle() } label: {
            Image(systemName: VyronSymbols.notifications)
                .font(VyronNotificationStyle.bell)
                .foregroundStyle(Palette.text)
                .frame(width: VyronNotificationStyle.bellSize, height: VyronNotificationStyle.bellSize)
                .background(isPresented ? Palette.selection : Color.clear, in: RoundedRectangle(
                    cornerRadius: VyronNotificationStyle.bellRadius
                ))
                .overlay(RoundedRectangle(cornerRadius: VyronNotificationStyle.bellRadius).stroke(
                    isPresented ? Palette.controlAccent : Color.clear,
                    lineWidth: VyronNotificationStyle.bellBorderWidth
                ))
                .overlay(alignment: .topTrailing) {
                    if model.unreadNotificationCount > 0 {
                        Circle().fill(Palette.controlAccent)
                            .frame(
                                width: VyronNotificationStyle.bellUnreadSize,
                                height: VyronNotificationStyle.bellUnreadSize
                            )
                            .overlay(Circle().stroke(
                                VyronSidebarStyle.background,
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
