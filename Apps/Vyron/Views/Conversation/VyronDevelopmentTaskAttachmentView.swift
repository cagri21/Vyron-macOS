import SwiftUI
import UniformTypeIdentifiers

struct VyronDevelopmentTaskAttachmentView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @State private var isPreviewPresented = false
    @State private var isExportPresented = false
    @State private var exportError: String?

    let filename: String
    let content: String

    private static let previewHeight: CGFloat = 440

    var body: some View {
        let _ = localizationLocale
        Button {
            exportError = nil
            isPreviewPresented = true
        } label: {
            Label {
                Text(verbatim: filename)
            } icon: {
                Image(systemName: VyronSymbols.files).foregroundStyle(palette.accent)
            }
            .font(VyronWorkspaceStyle.controlFont)
            .padding(VyronWorkspaceStyle.compactSpacing)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPreviewPresented) { preview }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.controlSpacing) {
            HStack {
                Text(verbatim: filename).font(VyronWorkspaceStyle.inputFont)
                Spacer()
                Button(VyronHeaderText.save) {
                    exportError = nil
                    isExportPresented = true
                }
                Button(VyronScreenshotText.close) { isPreviewPresented = false }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(verbatim: content)
                    .font(VyronConversationStyle.prose)
                    .lineSpacing(VyronConversationStyle.proseLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let exportError {
                Text(verbatim: exportError)
                    .font(VyronWorkspaceStyle.captionFont)
                    .foregroundStyle(palette.warning)
                    .textSelection(.enabled)
            }
        }
        .padding(VyronWorkspaceStyle.outerPadding)
        .frame(width: VyronWorkspaceStyle.contentWidth, height: Self.previewHeight)
        .background(palette.canvas)
        .fileExporter(
            isPresented: $isExportPresented,
            document: VyronDevelopmentTaskTextDocument(content: content),
            contentType: .plainText,
            defaultFilename: filename
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
    }
}
