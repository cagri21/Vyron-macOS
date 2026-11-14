import SwiftUI

struct VyronOpenAIBillingPage: View {
    @Environment(\.vyronPalette) private var palette
    @ObservedObject var browser: VyronBillingBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: VyronBillingStyle.detailSpacing) {
            HStack(spacing: VyronBillingStyle.toolbarSpacing) {
                VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
                    Text(VyronBillingText.officialPage).font(VyronSettingsStyle.body)
                    if let host = browser.state.host {
                        Text(verbatim: host).font(VyronSettingsStyle.detail).foregroundStyle(palette.muted)
                    }
                }
                Spacer(minLength: 0)
                if browser.state.phase == .loading { ProgressView().controlSize(.small) }
                Button { browser.open() } label: {
                    Image(systemName: VyronSymbols.refresh)
                }
                .help(VyronBalanceText.refresh)
                .accessibilityLabel(VyronBalanceText.refresh)
                if let url = VyronBillingDashboard.openAI {
                    Link(destination: url) { Image(systemName: VyronSymbols.externalOpen) }
                        .help(VyronBillingText.openBrowser)
                        .accessibilityLabel(VyronBillingText.openBrowser)
                }
                Button { browser.close() } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .help(VyronBillingText.closePage)
                .accessibilityLabel(VyronBillingText.closePage)
            }
            .buttonStyle(QuietButtonStyle(foreground: palette.text))
            Text(VyronBillingText.organizationHint)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if browser.state.phase == .failed || browser.state.phase == .browserSignInRequired {
                Text(browser.state.phase == .failed ? VyronBillingText.loadFailed : VyronBillingText.browserSignIn)
                    .font(VyronSettingsStyle.body)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VyronBillingWebView(browser: browser)
                .frame(minHeight: VyronBillingStyle.browserMinimumHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: VyronBillingStyle.browserRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: VyronBillingStyle.browserRadius).stroke(palette.border)
                }
        }
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
