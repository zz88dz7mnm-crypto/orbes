import SwiftUI
import OrbexCore

/// Configuración › Integraciones: cada servicio con su interruptor y su clave en el Keychain.
/// Todo es de solo lectura; ORBEX solo habla con los servicios que conectes.
struct IntegrationsSettingsView: View {
    @ObservedObject private var hub = IntegrationsHub.shared

    var body: some View {
        Form {
            Section {
                Text("Solo lectura. Las claves quedan en el Keychain de tu Mac y nunca se muestran de nuevo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(IntegrationID.allCases) { id in
                IntegrationSection(id: id, hub: hub)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntegrationSection: View {
    let id: IntegrationID
    @ObservedObject var hub: IntegrationsHub
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var testing = false
    @AppStorage private var enabled: Bool
    @AppStorage private var baseURL: String
    @AppStorage private var team: String

    init(id: IntegrationID, hub: IntegrationsHub) {
        self.id = id
        self.hub = hub
        _enabled = AppStorage(wrappedValue: false, "orbex.integrations.\(id.rawValue).enabled")
        _baseURL = AppStorage(wrappedValue: "", "orbex.integrations.\(id.rawValue).baseURL")
        _team = AppStorage(wrappedValue: "", "orbex.integrations.\(id.rawValue).team")
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { on in
                enabled = on
                hub.setEnabled(id, on)
            })) {
                Label(id.title, systemImage: id.symbol)
            }
            if enabled {
                HStack {
                    SecureField(hasKey ? "Clave guardada ✓ (escribí otra para reemplazarla)" : "Clave / token", text: $keyInput)
                        .onSubmit(saveKey)
                    Button("Guardar", action: saveKey)
                        .disabled(keyInput.isEmpty)
                    if hasKey {
                        Button("Quitar", role: .destructive) {
                            Keychain.set(nil, for: id.keychainAccount)
                            hasKey = false
                        }
                    }
                }
                Text(id.keyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if id.needsBaseURL {
                    TextField("URL de tu n8n (https://…)", text: $baseURL)
                }
                if id.needsTeamOrProject {
                    TextField("Equipo o proyecto (opcional)", text: $team)
                }
                HStack {
                    Button(testing ? "Probando…" : "Probar") {
                        testing = true
                        Task { @MainActor in
                            await hub.refresh(id)
                            testing = false
                        }
                    }
                    .disabled(testing || !hasKey)
                    if let status = hub.status[id] {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .onAppear { hasKey = Keychain.has(id.keychainAccount) }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.set(key, for: id.keychainAccount)
        keyInput = ""
        hasKey = true
    }
}
