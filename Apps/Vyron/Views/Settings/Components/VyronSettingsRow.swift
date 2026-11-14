import SwiftUI

struct VyronSettingsRow<Control: View>: View {
    @Environment(\.vyronPalette) private var palette
    private let title: String
    private let detail: String
    private let control: Control

    init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: VyronSettingsStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
                Text(verbatim: title)
                    .font(VyronSettingsStyle.body)
                    .foregroundStyle(palette.text)
                Text(verbatim: detail)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .font(VyronSettingsStyle.detail)
                .controlSize(.small)
        }
        .padding(.vertical, VyronSettingsStyle.rowPadding)
        .accessibilityElement(children: .contain)
    }
}
