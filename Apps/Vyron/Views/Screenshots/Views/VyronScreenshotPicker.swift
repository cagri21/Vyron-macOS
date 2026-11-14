import SwiftUI

struct VyronScreenshotPicker: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var localizationLocale
    @StateObject private var state = VyronScreenshotPickerState()

    let onCapture: (Data, String) -> Void

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronScreenshotPickerStyle.spacing) {
            Text(VyronScreenshotText.pickerTitle)
                .font(VyronScreenshotPickerStyle.title)
            Text(VyronScreenshotText.pickerHint)
                .foregroundStyle(palette.muted)
            sources
            if let error = state.errorMessage {
                Label {
                    Text(verbatim: error).textSelection(.enabled)
                } icon: {
                    Image(systemName: VyronSymbols.warning)
                }
                .foregroundStyle(palette.warning)
            }
            if state.needsPermission {
                HStack(spacing: VyronScreenshotPickerStyle.rowSpacing) {
                    Button(VyronScreenshotText.permissionTitle) { state.requestPermission() }
                    Button(VyronScreenshotText.openSettings) { state.openPermissionSettings() }
                }
            }
            actions
        }
        .font(VyronScreenshotPickerStyle.body)
        .padding(VyronScreenshotPickerStyle.padding)
        .frame(width: VyronScreenshotPickerStyle.width)
        .background(palette.canvas)
        .onAppear { state.start() }
        .onDisappear { state.stop() }
    }

    private var sources: some View {
        Group {
            if state.isLoading {
                ProgressView(VyronScreenshotText.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.sources.isEmpty {
                Text(VyronScreenshotText.noSources)
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $state.selectedSourceID) {
                    ForEach(state.sources) { source in
                        HStack(spacing: VyronScreenshotPickerStyle.rowSpacing) {
                            Image(systemName: VyronSymbols.computerPreview)
                                .foregroundStyle(palette.muted)
                            VStack(alignment: .leading, spacing: VyronScreenshotPickerStyle.compactSpacing) {
                                Text(verbatim: source.name).lineLimit(2)
                                Text(
                                    source.kind == .window
                                        ? VyronScreenshotText.windowKind : VyronScreenshotText.displayKind
                                )
                                    .font(VyronScreenshotPickerStyle.caption)
                                    .foregroundStyle(palette.muted)
                            }
                        }
                        .tag(source.id)
                    }
                }
                .disabled(state.isCapturing)
            }
        }
        .frame(height: VyronScreenshotPickerStyle.sourceListHeight)
    }

    private var actions: some View {
        HStack(spacing: VyronScreenshotPickerStyle.rowSpacing) {
            Button {
                state.refresh()
            } label: {
                Label(VyronScreenshotText.refresh, systemImage: VyronSymbols.refresh)
            }
            .disabled(state.isCapturing)
            Spacer(minLength: 0)
            Button(VyronScreenshotText.cancel) {
                state.stop()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(state.isCapturing ? VyronScreenshotText.capturing : VyronScreenshotText.capture) {
                state.captureSelection { data, name in
                    onCapture(data, name)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!state.canCapture)
        }
    }
}
