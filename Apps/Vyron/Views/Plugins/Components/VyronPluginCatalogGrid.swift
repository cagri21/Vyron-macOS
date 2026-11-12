import SwiftUI

struct VyronPluginCatalogGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: VyronPluginsStyle.minimumCardWidth), spacing: VyronPluginsStyle.columnSpacing),
            GridItem(.flexible(minimum: VyronPluginsStyle.minimumCardWidth), spacing: VyronPluginsStyle.columnSpacing)
        ]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: columns, spacing: VyronPluginsStyle.compactSpacing) {
                content
            }
            .frame(minWidth: VyronPluginsStyle.minimumCardWidth * 2 + VyronPluginsStyle.columnSpacing)
            LazyVStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
