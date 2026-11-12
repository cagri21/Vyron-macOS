import SwiftUI

struct VyronOpenAIBillingCard: View {
    @Environment(\.locale) private var localizationLocale
    let open: () -> Void

    var body: some View {
        let _ = localizationLocale
        VyronSettingsCard {
            VStack(alignment: .leading, spacing: VyronBillingStyle.detailSpacing) {
                Label(VyronBillingText.openAI, systemImage: VyronSymbols.balance)
                    .font(VyronBillingStyle.heading)
                Text(VyronBillingText.apiCreditBalance)
                    .foregroundStyle(Palette.text)
                Text(VyronBillingText.openAIDescription)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: VyronBillingStyle.toolbarSpacing) {
                    Button(VyronBillingText.viewBalance, action: open)
                        .buttonStyle(QuietButtonStyle(foreground: Palette.text))
                    if let url = VyronBillingDashboard.openAI {
                        Link(VyronBillingText.openBrowser, destination: url)
                            .foregroundStyle(Palette.text)
                    }
                }
                .padding(.top, VyronBillingStyle.detailSpacing)
            }
            .font(VyronSettingsStyle.body)
            .foregroundStyle(Palette.text)
            .padding(.vertical, VyronBillingStyle.cardPadding)
        }
    }
}
