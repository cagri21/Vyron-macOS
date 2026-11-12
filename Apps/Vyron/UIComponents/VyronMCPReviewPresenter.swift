import SwiftUI

struct VyronMCPReviewPresenter: ViewModifier {
    @ObservedObject var connections: MCPConnectionsModel
    let canPresent: () -> Bool

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { canPresent() && connections.pendingReview != nil },
                set: { _ in }
            )
        ) {
            VyronMCPActionReviewView(connections: connections, canRespond: canPresent)
                .interactiveDismissDisabled()
        }
    }
}
