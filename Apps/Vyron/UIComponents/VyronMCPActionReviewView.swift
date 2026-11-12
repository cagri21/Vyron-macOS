import SwiftUI

struct VyronMCPActionReviewView: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var connections: MCPConnectionsModel
    let canRespond: () -> Bool

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronMCPStyle.reviewSpacing) {
            Text(VyronPluginText.reviewTitle).font(VyronMCPStyle.reviewTitle)
            if let request = connections.pendingReview {
                Text("\(request.connectionName) · \(request.toolName)").font(VyronMCPStyle.reviewIdentity)
                Text(VyronPluginText.reviewDescription)
                    .font(VyronMCPStyle.reviewBody).foregroundStyle(Palette.muted)
                ScrollView {
                    Text(request.arguments).font(VyronMCPStyle.code).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(VyronMCPStyle.reviewArgumentsPadding)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronMCPStyle.reviewArgumentsRadius))
                Text(VyronPluginText.reviewRetryWarning)
                    .font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
                HStack {
                    Spacer()
                    Button(VyronPluginText.reviewDecline, role: .cancel) { respond(false, to: request.id) }
                        .buttonStyle(QuietButtonStyle())
                    Button(VyronPluginText.reviewAllow) { respond(true, to: request.id) }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }.padding(VyronMCPStyle.reviewPadding)
            .frame(width: VyronMCPStyle.reviewSize.width, height: VyronMCPStyle.reviewSize.height)
            .background(Palette.canvas).foregroundStyle(Palette.text)
    }

    private func respond(_ approved: Bool, to requestID: UUID) {
        guard canRespond(), connections.pendingReview?.id == requestID else { return }
        connections.respondToReview(approved)
    }
}
