import SwiftUI

struct VyronOpenAIBillingCard: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    let open: () -> Void

    var body: some View {
        let _ = localizationLocale
        VyronSettingsCard {
            VStack(alignment: .leading, spacing: VyronBillingStyle.detailSpacing) {
                Label(VyronBillingText.openAI, systemImage: VyronSymbols.balance)
                    .font(VyronBillingStyle.heading)
                Text(VyronBillingText.apiCreditBalance)
                    .foregroundStyle(palette.text)
                Text(VyronBillingText.openAIDescription)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: VyronBillingStyle.toolbarSpacing) {
                    Button(VyronBillingText.viewBalance, action: open)
                        .buttonStyle(QuietButtonStyle(foreground: palette.text))
                    if let url = VyronBillingDashboard.openAI {
                        Link(VyronBillingText.openBrowser, destination: url)
                            .foregroundStyle(palette.text)
                    }
                }
                .padding(.top, VyronBillingStyle.detailSpacing)
            }
            .font(VyronSettingsStyle.body)
            .foregroundStyle(palette.text)
            .padding(.vertical, VyronBillingStyle.cardPadding)
        }
    }
}
