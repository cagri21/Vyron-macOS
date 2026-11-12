import SwiftUI
import VyronCore

struct VyronMCPConnectionEditor: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject var connections: MCPConnectionsModel
    let initial: MCPConnectionProfile
    @Environment(\.dismiss) private var dismiss
    @State private var profile: MCPConnectionProfile
    @State private var arguments = ""
    @State private var token = ""
    @State private var headers = "{}"
    @State private var environment = "{}"
    @State private var queries = "{}"
    @State private var jsonMode = false
    @State private var configurationJSON = ""
    @State private var error: String?
    @State private var credentialsLoaded = false
    @State private var credentialDestination = ""

    init(connections: MCPConnectionsModel, initial: MCPConnectionProfile) {
        self.connections = connections; self.initial = initial
        _profile = State(initialValue: initial)
        _arguments = State(initialValue: initial.arguments.joined(separator: "\n"))
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronMCPStyle.editorContainerSpacing) {
            HStack {
                Text(VyronPluginText.editorTitle).font(VyronMCPStyle.editorTitle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: VyronSymbols.close)
                }.buttonStyle(QuietButtonStyle())
                    .accessibilityLabel(VyronPluginText.close)
            }.padding(VyronMCPStyle.editorPadding)
            Divider().overlay(Palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: VyronMCPStyle.editorSectionSpacing) {
                    Toggle(
                        VyronPluginText.editorJSONMode,
                        isOn: Binding(get: { jsonMode }, set: setJSONMode)
                    ).font(VyronMCPStyle.field)
                    if jsonMode {
                        Text(VyronPluginText.editorJSONHint)
                            .font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
                        jsonEditor(
                            VyronPluginText.editorConnectionJSON,
                            text: $configurationJSON,
                            height: VyronMCPStyle.configurationEditorHeight
                        )
                    } else {
                        LabeledContent(VyronPluginText.editorName) {
                            TextField(VyronPluginText.penpotName, text: $profile.name).textFieldStyle(.roundedBorder)
                        }
                        Picker(VyronPluginText.editorConnection, selection: $profile.transport) {
                            ForEach(MCPTransport.allCases) { transport in
                                Text(
                                    transport == .http
                                        ? VyronPluginText.editorTransportHTTP : VyronPluginText.editorTransportStdio
                                ).tag(transport)
                            }
                        }
                        if profile.transport == .http {
                            LabeledContent(VyronPluginText.transportHTTP) {
                                TextField(VyronPluginText.editorEndpointPlaceholder, text: $profile.endpoint)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text(VyronPluginText.editorTokenURLHint)
                                .font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
                        } else {
                            LabeledContent(VyronPluginText.editorExecutable) {
                                TextField(VyronPluginText.editorExecutablePlaceholder, text: $profile.command)
                                    .textFieldStyle(.roundedBorder)
                            }
                            jsonEditor(
                                VyronPluginText.editorArguments,
                                text: $arguments,
                                height: VyronMCPStyle.credentialEditorHeight
                            )
                            Text(VyronPluginText.editorCommandHint)
                                .font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
                                .lineSpacing(VyronMCPStyle.commandHintLineSpacing)
                        }
                        Picker(VyronPluginText.editorToolAccess, selection: $profile.permission) {
                            ForEach(MCPPermission.allCases) { permission in
                                Text(
                                    permission == .readOnly
                                        ? VyronPluginText.permissionReadOnly : VyronPluginText.permissionReview
                                ).tag(permission)
                            }
                        }
                    }
                    LabeledContent(VyronPluginText.editorBearerToken) {
                        SecureField(VyronPluginText.editorOptional, text: $token).textFieldStyle(.roundedBorder)
                    }
                    DisclosureGroup(VyronPluginText.editorAdvancedCredentials) {
                        VStack(alignment: .leading, spacing: VyronMCPStyle.credentialsSpacing) {
                            jsonEditor(
                                VyronPluginText.editorHeadersJSON,
                                text: $headers,
                                height: VyronMCPStyle.credentialEditorHeight
                            )
                            jsonEditor(
                                VyronPluginText.editorParametersJSON,
                                text: $queries,
                                height: VyronMCPStyle.credentialEditorHeight
                            )
                            jsonEditor(
                                VyronPluginText.editorEnvironmentJSON,
                                text: $environment,
                                height: VyronMCPStyle.credentialEditorHeight
                            )
                        }.padding(.top, VyronMCPStyle.credentialsSpacing)
                    }
                    Text(VyronPluginText.editorPermissionsHint)
                        .font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
                        .lineSpacing(VyronMCPStyle.permissionsHintLineSpacing)
                    if let error {
                        Text(error).foregroundStyle(Palette.warning).font(VyronMCPStyle.field).textSelection(.enabled)
                    }
                }.font(VyronMCPStyle.field).padding(VyronMCPStyle.editorPadding)
            }
            Divider().overlay(Palette.border)
            HStack {
                Spacer()
                Button(VyronPluginText.cancel) { dismiss() }.buttonStyle(QuietButtonStyle())
                Button(VyronPluginText.editorSave) { save() }.buttonStyle(AccentButtonStyle()).disabled(
                    !credentialsLoaded || !model.canManageMCPConnections
                )
            }.padding(VyronMCPStyle.editorFooterPadding)
        }.frame(
            width: VyronMCPStyle.editorSize.width,
            height: VyronMCPStyle.editorSize.height
        )
        .background(Palette.canvas).foregroundStyle(Palette.text).tint(Palette.controlAccent)
        .onAppear { loadCredentials() }
        .onChange(of: profile) { _, value in
            if !jsonMode { clearCredentialsIfDestinationChanged(value) }
        }
        .onChange(of: configurationJSON) { _, value in
            if jsonMode,
                let decoded = try? JSONDecoder().decode(VyronMCPConnectionJSON.self, from: Data(value.utf8)) {
                clearCredentialsIfDestinationChanged(decoded.profile(id: initial.id))
            }
        }
    }

    private func jsonEditor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: VyronMCPStyle.jsonFieldSpacing) {
            Text(title).font(VyronMCPStyle.helper).foregroundStyle(Palette.muted)
            TextEditor(text: text).font(VyronMCPStyle.code).scrollContentBackground(.hidden)
                .padding(VyronMCPStyle.jsonFieldPadding).frame(height: height)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronMCPStyle.jsonFieldRadius))
                .overlay(RoundedRectangle(cornerRadius: VyronMCPStyle.jsonFieldRadius).stroke(Palette.border))
                .accessibilityLabel(title)
        }
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    private func loadCredentials() {
        guard !credentialsLoaded else { return }
        do {
            let secrets = try connections.secrets(for: profile.id)
            token = secrets.bearerToken; headers = try encoded(secrets.headers)
            environment = try encoded(secrets.environment); queries = try encoded(secrets.queryParameters)
            credentialDestination = destination(initial) ?? ""
            credentialsLoaded = true
        } catch { self.error = error.localizedDescription }
    }
    private func setJSONMode(_ enabled: Bool) {
        if enabled {
            buildJSON()
            jsonMode = true
        } else {
            do {
                let decoded = try JSONDecoder().decode(
                    VyronMCPConnectionJSON.self,
                    from: Data(configurationJSON.utf8)
                )
                profile = decoded.profile(id: initial.id)
                arguments = profile.arguments.joined(separator: "\n")
                clearCredentialsIfDestinationChanged(profile)
                jsonMode = false
                error = nil
            } catch { self.error = VyronPluginText.editorInvalidForm }
        }
    }
    private func destination(_ profile: MCPConnectionProfile) -> String? {
        if profile.transport == .stdio {
            let command = profile.command.trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : "stdio:\(command)"
        }
        guard let parts = URLComponents(string: profile.endpoint),
            let scheme = parts.scheme,
            let host = parts.host else {
            return nil
        }
        return "\(scheme.lowercased())://\(host.lowercased()):\(parts.port ?? (scheme.lowercased() == "https" ? 443 : 80))"
    }
    private func clearCredentialsIfDestinationChanged(_ profile: MCPConnectionProfile) {
        guard credentialsLoaded,
            let newDestination = destination(profile),
            newDestination != credentialDestination else {
            return
        }
        let hadCredentials = !token.isEmpty || [headers, queries, environment].contains { json in
            (try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)).isEmpty) != true
        }
        token = ""; headers = "{}"; queries = "{}"; environment = "{}"
        credentialDestination = newDestination
        if hadCredentials {
            error = VyronPluginText.editorServerChanged
        }
    }
    private func buildJSON() {
        profile.arguments = arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
        do { configurationJSON = try encoded(VyronMCPConnectionJSON(profile)) } catch {
            self.error = VyronPluginText.editorUnavailableJSON
        }
    }
    private func save() {
        guard credentialsLoaded, model.canManageMCPConnections else { return }
        do {
            var candidate =
                jsonMode
                ? try JSONDecoder().decode(VyronMCPConnectionJSON.self, from: Data(configurationJSON.utf8)).profile(
                    id: initial.id
                ) : profile
            if !jsonMode { candidate.arguments = arguments.components(separatedBy: .newlines).filter { !$0.isEmpty } }
            var query = try JSONDecoder().decode([String: String].self, from: Data(queries.utf8))
            if candidate.transport == .http {
                let separated = try MCPEndpoint.separateSecrets(candidate.endpoint)
                candidate.endpoint = separated.endpoint
                query.merge(separated.queryParameters) { _, new in new }
            }
            let secrets = MCPConnectionSecrets(
                bearerToken: token,
                headers: try JSONDecoder().decode([String: String].self, from: Data(headers.utf8)),
                environment: try JSONDecoder().decode([String: String].self, from: Data(environment.utf8)),
                queryParameters: query
            )
            guard connections.save(candidate, secrets: secrets) else { error = connections.error; return }
            dismiss()
        } catch is DecodingError {
            error = VyronPluginText.editorInvalidJSON
        } catch { self.error = error.localizedDescription }
    }
}
