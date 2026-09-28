import AppKit
import SwiftUI
import OrbexCore

/// Configuración › Asistente: Claude vía el CLI `claude` local (sin claves de API).
struct AssistantSettingsView: View {
    @AppStorage("orbex.assistant.model") private var model = ""
    @AppStorage("orbex.assistant.workingFolder") private var workingFolder = ""
    @AppStorage("orbex.assistant.allowTools") private var allowTools = false
    @AppStorage("orbex.assistant.maxHistory") private var maxHistory = 20
    @AppStorage("orbex.assistant.extraInstructions") private var extraInstructions = ""

    @State private var cliPath: String?
    @State private var cliVersion: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Claude Code en esta Mac") {
                HStack {
                    Image(systemName: cliPath == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(cliPath == nil ? Color.orange : Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cliPath == nil ? (checking ? "Buscando `claude`…" : "No encontré `claude`") : "Listo para usar")
                        if let cliPath {
                            Text(cliPath).font(.caption).foregroundStyle(.secondary)
                        }
                        if let cliVersion {
                            Text(cliVersion).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Volver a buscar") { detect() }
                        .disabled(checking)
                }
                if cliPath == nil && !checking {
                    Text("Instalá Claude Code y logueate corriendo `claude` una vez en la Terminal. ORBEX usa tu suscripción: no hace falta ninguna clave de API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Modelo") {
                TextField("Modelo (vacío = el que use Claude Code)", text: $model)
                Text("Ejemplos: sonnet, opus, haiku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Carpeta de trabajo") {
                HStack {
                    Text(workingFolder.isEmpty ? "Carpeta propia de ORBEX" : workingFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Elegir…") { chooseFolder() }
                    if !workingFolder.isEmpty {
                        Button("Restablecer") { workingFolder = "" }
                    }
                }
            }

            Section("Permisos") {
                Toggle("Permitir herramientas (leer/editar archivos, correr comandos)", isOn: $allowTools)
                Text(allowTools
                     ? "⚠️ Claude va a poder tocar archivos de la carpeta de trabajo. Usalo con cuidado."
                     : "Recomendado: apagado. El asistente solo conversa.")
                    .font(.caption)
                    .foregroundStyle(allowTools ? Color.orange : Color.secondary)
            }

            Section("Conversación") {
                Stepper("Historial máximo: \(maxHistory) mensajes", value: $maxHistory, in: 4...100, step: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instrucciones extra para Claude")
                    TextEditor(text: $extraInstructions)
                        .font(.system(size: 12))
                        .frame(minHeight: 70)
                }
                Text("Cada respuesta usa tu cuota de Claude Code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { detect() }
    }

    private func detect() {
        checking = true
        Task { @MainActor in
            let found = await ClaudeCLI.shared.detect()
            cliPath = found.path
            cliVersion = found.version
            checking = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url {
            workingFolder = url.path
        }
    }
}
