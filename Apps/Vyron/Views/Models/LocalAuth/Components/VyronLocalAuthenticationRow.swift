import SwiftUI
import VyronCore

struct VyronLocalAuthenticationRow: View {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @ObservedObject var authentication: VyronLocalAuthenticationModel

    var body: some View {
        let _ = locale
        VyronSettingsRow(VyronLocalAuthText.title, detail: detail) {
            HStack(spacing: VyronSettingsStyle.rowSpacing) {
                if authentication.status == .connecting { ProgressView().controlSize(.small) }
                Text(verbatim: status).foregroundStyle(palette.muted)
                Button(VyronLocalAuthText.retry) { model.requestLocalCredentialSynchronization() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(authentication.status == .connecting || model.isShuttingDown)
            }
        }
    }

    private var status: String {
        switch authentication.status {
        case .notConfigured: VyronLocalAuthText.notConfigured
        case .connecting: VyronLocalAuthText.connecting
        case .connected: VyronLocalAuthText.connected
        case .unavailable: VyronLocalAuthText.unavailable
        }
    }

    private var detail: String {
        guard let failure = authentication.failure else { return VyronLocalAuthText.description }
        return switch failure {
        case .credentialsUnavailable: VyronLocalAuthText.credentialsUnavailable
        case .encryptionKeyMissing: VyronLocalAuthText.encryptionKeyMissing
        case .unauthorized: VyronLocalAuthText.unauthorized
        case .invalidConfiguration: VyronLocalAuthText.invalidConfiguration
        case .integrityFailed: VyronLocalAuthText.integrityFailed
        case .invalidResponse, .unavailable, .conflict: VyronLocalAuthText.serviceUnavailable
        }
    }
}
