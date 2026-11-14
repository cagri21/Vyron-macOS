import AppKit
import SwiftUI
import VyronAutomation

struct VyronPermissionsSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @State private var model: VyronPermissionsViewModel

    init(model: VyronPermissionsViewModel = VyronPermissionsViewModel(access: .system)) {
        _model = State(initialValue: model)
    }

    var body: some View {
        let _ = localizationLocale
        @Bindable var model = model
        VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
            HStack(alignment: .center, spacing: VyronSettingsStyle.rowSpacing) {
                Text(verbatim: VyronPermissionsText.description)
                    .font(VyronSettingsStyle.body)
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: model.refresh) {
                    Label(VyronAppText.settingsRefresh, systemImage: VyronSymbols.refresh)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            VyronSettingsCard {
                ForEach(VyronMacPrivacyPane.allCases, id: \.self) { pane in
                    if pane != VyronMacPrivacyPane.allCases.first {
                        Divider().overlay(palette.border)
                    }
                    permissionRow(for: pane)
                }
            }
        }
        .onAppear(perform: model.refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .task(id: model.pendingRequest) {
            await model.requestPendingAccess()
        }
        .alert(VyronPermissionsText.title, isPresented: $model.showsSettingsError) {
            Button(VyronPluginText.close, role: .cancel) {}
        } message: {
            Text(verbatim: VyronPermissionsText.openSystemSettingsFailed)
        }
    }

    private func permissionRow(for pane: VyronMacPrivacyPane) -> some View {
        let status = model.status(for: pane)
        return VyronSettingsRow(title(for: pane), detail: detail(for: pane)) {
            VStack(alignment: .trailing, spacing: VyronSettingsStyle.textSpacing) {
                Label(
                    statusText(status),
                    systemImage: status == .granted ? VyronSymbols.checkCircle : VyronSymbols.details
                )
                .foregroundStyle(status == .granted ? palette.success : palette.muted)
                Button {
                    model.openSettings(for: pane)
                } label: {
                    Label(VyronPermissionsText.openSystemSettings, systemImage: VyronSymbols.externalOpen)
                }
                .buttonStyle(.bordered)
                if status == .notRequested {
                    Button(VyronPermissionsText.requestAccess) {
                        model.queueRequest(for: pane)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.pendingRequest != nil)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func title(for pane: VyronMacPrivacyPane) -> String {
        switch pane {
        case .accessibility:
            if #available(macOS 27.0, *) { return VyronPermissionsText.deviceControl }
            return VyronPermissionsText.accessibility
        case .screenRecording: return VyronPermissionsText.screenRecording
        case .microphone: return VyronPermissionsText.microphone
        case .speechRecognition: return VyronPermissionsText.speechRecognition
        }
    }

    private func detail(for pane: VyronMacPrivacyPane) -> String {
        switch pane {
        case .accessibility: VyronPermissionsText.accessibilityDescription
        case .screenRecording: VyronPermissionsText.screenRecordingDescription
        case .microphone: VyronPermissionsText.microphoneDescription
        case .speechRecognition: VyronPermissionsText.speechRecognitionDescription
        }
    }

    private func statusText(_ status: VyronPermissionStatus) -> String {
        switch status {
        case .granted: VyronPermissionsText.granted
        case .notGranted: VyronPermissionsText.notGranted
        case .notRequested: VyronPermissionsText.notRequested
        case .restricted: VyronPermissionsText.restricted
        case .unavailable: VyronPermissionsText.unavailable
        }
    }
}
