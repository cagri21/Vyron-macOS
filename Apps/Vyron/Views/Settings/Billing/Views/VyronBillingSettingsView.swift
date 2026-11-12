import SwiftUI
import VyronCore

struct VyronBillingSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @StateObject private var browser = VyronBillingBrowserModel()

    var body: some View {
        let _ = localizationLocale
        Group {
            if browser.request != nil {
                VyronOpenAIBillingPage(browser: browser)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: VyronBillingStyle.sectionSpacing) {
                        VyronOpenAIBillingCard(open: browser.open)
                        ForEach(reportedConnections) { profile in
                            VyronBillingConnectionCard(balances: model.connectionBalances, profile: profile)
                        }
                    }
                    .frame(maxWidth: VyronSettingsStyle.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, VyronSettingsStyle.contentPadding)
        .padding(.bottom, VyronSettingsStyle.contentPadding)
        .onDisappear { browser.close() }
    }

    private var reportedConnections: [ModelConnectionProfile] {
        model.modelSelection.connectionProfiles.filter { VyronConnectionBalancePolicy.support(for: $0).canFetch }
    }
}
