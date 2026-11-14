import SwiftUI

struct VyronAppearanceRow<Control: View>: View {
    @Environment(\.vyronPalette) private var palette
    private let title: String
    private let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: VyronSettingsStyle.rowSpacing) {
            Text(verbatim: title)
                .font(VyronSettingsStyle.body)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .frame(minHeight: VyronAppearanceSettingsStyle.rowHeight)
        .accessibilityElement(children: .contain)
    }
}
