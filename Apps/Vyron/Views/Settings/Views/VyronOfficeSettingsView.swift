import AppKit
import SwiftUI
import VyronCore

struct VyronOfficeSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @AppStorage(VyronUserDefaultsKey.officePythonExecutable.rawValue) private var pythonExecutable = ""
    @State private var status: VyronOfficeRuntimeStatus?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var checkID: UUID?

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
            Text(VyronOfficeText.title).font(VyronSettingsStyle.sectionTitle)
            Text(VyronOfficeText.description)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(pythonExecutable.isEmpty ? VyronOfficeText.automaticRuntime : pythonExecutable)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(palette.muted)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(VyronOfficeText.runtimeExecutable)
                if !pythonExecutable.isEmpty {
                    Button(VyronOfficeText.useAutomatic) { pythonExecutable = "" }
                        .buttonStyle(.bordered)
                }
                Button(VyronOfficeText.chooseRuntime) { chooseRuntime() }
                    .buttonStyle(.bordered)
            }
            Text(VyronOfficeText.setupHint)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(VyronOfficeText.checkSetup) { checkSetup() }
                    .buttonStyle(.bordered)
                    .disabled(checkID != nil)
                if checkID != nil { ProgressView().controlSize(.small) }
                if let status {
                    Text(status.isAvailable ? VyronOfficeText.ready : VyronOfficeText.setupRequired)
                        .font(VyronSettingsStyle.detail)
                        .foregroundStyle(status.isAvailable ? palette.success : palette.warning)
                }
            }
            if let status {
                DisclosureGroup(VyronOfficeText.setupDetails) {
                    Text(status.isAvailable ? VyronOfficeText.readyDetails : VyronOfficeText.missingRuntimeDetails)
                        .font(VyronSettingsStyle.detail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let executable = status.pythonExecutable {
                        Text(verbatim: executable)
                            .font(VyronSettingsStyle.detail)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(VyronSettingsStyle.detail)
            }
            if let failure {
                Text(verbatim: failure)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, VyronSettingsStyle.rowPadding)
        .onChange(of: pythonExecutable) { _, _ in
            cancelCheck()
            status = nil
            failure = nil
        }
        .onDisappear { cancelCheck() }
    }

    private func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.title = VyronOfficeText.chooseRuntime
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pythonExecutable = url.path
    }

    private func checkSetup() {
        cancelCheck()
        let id = UUID()
        checkID = id
        status = nil
        failure = nil
        let runtime = VyronOfficeRuntime(configuration: VyronOfficePreferences.configuration())
        task = Task { @MainActor in
            defer {
                if checkID == id { checkID = nil; task = nil }
            }
            do {
                let result = try await runtime.status()
                try Task.checkCancellation()
                guard checkID == id else { return }
                status = result
            } catch {
                guard checkID == id, !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }

    private func cancelCheck() {
        checkID = nil
        task?.cancel()
        task = nil
    }
}
