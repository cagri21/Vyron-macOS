import SwiftUI
import VyronCore

struct VyronBillingConnectionCard: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var balances: VyronConnectionBalancesModel
    let profile: ModelConnectionProfile

    var body: some View {
        TimelineView(.periodic(from: .now, by: VyronConnectionBalanceStyle.displayRefreshInterval)) { _ in
            VyronSettingsCard {
                VStack(alignment: .leading, spacing: VyronBillingStyle.detailSpacing) {
                    Text(verbatim: profile.name).font(VyronBillingStyle.heading)
                    Text(verbatim: VyronConnectionBalancePresentation.badge(
                        state, locale: localizationLocale, isStale: balances.isStale(for: profile.id)
                    ))
                    .font(VyronBillingStyle.amount)
                    .monospacedDigit()
                    .textSelection(.enabled)
                    if let snapshot = state.snapshot {
                        Text(VyronConnectionBalancePresentation.scope(snapshot.scope)).foregroundStyle(Palette.muted)
                        HStack {
                            Text(VyronBalanceText.updated)
                            Text(snapshot.checkedAt, style: .date)
                            Text(snapshot.checkedAt, style: .time)
                        }
                        .font(VyronSettingsStyle.detail)
                        .foregroundStyle(Palette.muted)
                    }
                    Text(VyronConnectionBalancePresentation.explanation(state))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: VyronBillingStyle.toolbarSpacing) {
                        Button { balances.refresh(profile.id) } label: {
                            if state.isRefreshing { ProgressView().controlSize(.small) }
                            Text(VyronBalanceText.refresh)
                        }
                        .disabled(!balances.canRefresh(profile.id))
                        if let url = balances.billingURL(for: profile.id) {
                            Link(VyronBalanceText.openBilling, destination: url)
                        }
                    }
                    .buttonStyle(QuietButtonStyle(foreground: Palette.text))
                }
                .font(VyronSettingsStyle.body)
                .foregroundStyle(Palette.text)
                .padding(.vertical, VyronBillingStyle.cardPadding)
            }
        }
    }

    private var state: VyronConnectionBalanceState { balances.state(for: profile.id) }
}
