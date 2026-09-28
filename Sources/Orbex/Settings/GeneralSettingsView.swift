import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OrbexCore

/// Configuración › General: inicio con la Mac, acceso directo, atajos, bienvenida y copia de ajustes.
struct GeneralSettingsView: View {
    @ObservedObject var model = AppModel.shared
    @State private var loginStatus = ""
    @State private var loginNeedsApproval = false
    @State private var shortcutExists = false
    @State private var welcomeMessage: String?
    @State private var transferMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Iniciar con la Mac", isOn: $model.settings.launchAtLogin)
                LabeledContent("Estado") {
                    Text(loginStatus)
                        .foregroundStyle(.secondary)
                }
                if loginNeedsApproval {
                    HStack {
                        SettingsFootnote(text: "macOS pide que lo apruebes en Ajustes del Sistema › General › Ítems de inicio.",
                                         symbol: "exclamationmark.triangle")
                        Spacer()
                        Button("Abrir Ajustes del Sistema") {
                            LaunchAtLogin.openSystemSettings()
                        }
                    }
                }

                Toggle("Acceso directo en el Escritorio", isOn: $model.settings.desktopShortcut)
                if model.settings.desktopShortcut && !shortcutExists {
                    HStack {
                        SettingsFootnote(text: "No encuentro el acceso directo en el Escritorio (¿lo borraste?).",
                                         symbol: "questionmark.folder")
                        Spacer()
                        Button("Crearlo de nuevo") {
                            _ = DesktopShortcut.create()
                            refreshStatus()
                        }
                    }
                } else {
                    SettingsFootnote(text: shortcutExists
                                     ? "Hay un acceso directo a ORBEX en tu Escritorio."
                                     : "No hay acceso directo a ORBEX en el Escritorio.")
                }
            } header: {
                Text("Inicio")
            }

            Section {
                let hotkeys = OrbexHotKeys.descriptions
                ForEach(0..<hotkeys.count, id: \.self) { i in
                    LabeledContent(hotkeys[i].1) {
                        Text(hotkeys[i].0)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.08)))
                    }
                }
                SettingsFootnote(text: "Los atajos funcionan desde cualquier app.")
            } header: {
                Text("Atajos")
            }

            Section {
                HStack {
                    Text("Bienvenida")
                    Spacer()
                    Button("Volver a mostrar la bienvenida") {
                        model.settings.firstRunDone = false
                        welcomeMessage = "Listo: la bienvenida se va a mostrar la próxima vez que abras ORBEX."
                    }
                    .disabled(!model.settings.firstRunDone)
                }
                if let welcomeMessage {
                    SettingsFootnote(text: welcomeMessage, symbol: "checkmark.circle")
                }
            } header: {
                Text("Primer arranque")
            }

            Section {
                HStack {
                    Button("Exportar ajustes…") { exportSettings() }
                    Button("Importar ajustes…") { importSettings() }
                    Spacer()
                }
                if let transferMessage {
                    SettingsFootnote(text: transferMessage, symbol: "info.circle")
                }
                SettingsFootnote(text: "Se guardan en un archivo JSON. Las claves nunca se exportan: viven solo en el Llavero de la Mac.",
                                 symbol: "lock")
            } header: {
                Text("Copia de los ajustes")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshStatus() }
        .onChange(of: model.settings.launchAtLogin) { refreshStatus() }
        .onChange(of: model.settings.desktopShortcut) { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    // MARK: - Estado del sistema

    private func refreshStatus() {
        loginStatus = LaunchAtLogin.statusDescription
        loginNeedsApproval = LaunchAtLogin.needsApproval
        shortcutExists = DesktopShortcut.exists
    }

    // MARK: - Exportar / importar

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = "Exportar ajustes de ORBEX"
        panel.prompt = "Exportar"
        panel.nameFieldStringValue = "ORBEX-ajustes.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try model.settings.exportJSON()
            try data.write(to: url, options: .atomic)
            transferMessage = "Ajustes exportados en “\(url.lastPathComponent)”."
        } catch {
            transferMessage = "No se pudo exportar: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Importar ajustes de ORBEX"
        panel.prompt = "Importar"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            var imported = try OrbexSettings.importJSON(data)
            // Importar no tiene que volver a mostrar la bienvenida en esta Mac.
            imported.firstRunDone = model.settings.firstRunDone
            guard confirmImport() else { return }
            model.settings = imported
            transferMessage = "Ajustes importados de “\(url.lastPathComponent)”."
        } catch {
            transferMessage = "No se pudo leer el archivo: \(error.localizedDescription)"
        }
    }

    private func confirmImport() -> Bool {
        let alert = NSAlert()
        alert.messageText = "¿Reemplazar los ajustes actuales?"
        alert.informativeText = "Se aplican todos los ajustes del archivo (incluido iniciar con la Mac y el acceso directo). Las claves guardadas no se tocan."
        alert.addButton(withTitle: "Importar")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
