import SwiftUI

struct VyronWorkspaceRecentRow: View {
    @Environment(\.vyronPalette) private var palette
    let item: VyronWorkspaceRecentItem

    var body: some View {
        HStack(spacing: VyronWorkspaceToolsStyle.padding) {
            Image(systemName: symbol)
                .foregroundStyle(palette.controlAccent)
                .frame(width: VyronWorkspaceToolsStyle.iconWidth)
            VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.gridSpacing) {
                Text(item.title).font(VyronWorkspaceToolsStyle.controlFont).lineLimit(1)
                Text(kind).font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 0)
            Text(item.openedAt, style: .time)
                .font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(palette.muted)
        }
        .padding(VyronWorkspaceToolsStyle.padding)
        .contentShape(Rectangle())
        .help(item.kind == .page ? item.title : item.url.path.isEmpty ? item.url.absoluteString : item.url.path)
    }

    private var symbol: String {
        switch item.kind {
        case .page: VyronSymbols.newPage
        case .file: VyronSymbols.files
        case .link: VyronSymbols.web
        }
    }

    private var kind: String {
        switch item.kind {
        case .page: VyronToolsText.pageKind
        case .file: item.url.pathExtension.isEmpty ? VyronToolsText.fileKind : item.url.pathExtension.uppercased()
        case .link: item.url.host ?? VyronToolsText.websiteKind
        }
    }
}
