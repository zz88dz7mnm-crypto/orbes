import AppKit
import SwiftUI
import OrbexCore

/// Claves de ajustes de las utilidades (las leen TimersStore, NotesStore y CommandExecutor).
enum UtilitiesKeys {
    static let defaultTimerMinutes = "orbex.utilities.defaultTimerMinutes"
    static let timerSound = "orbex.utilities.timerSound"
    static let timerNotifications = "orbex.utilities.timerNotifications"
    static let notesDestination = "orbex.utilities.notesDestination"
    static let notesFolder = "orbex.utilities.notesFolder"
    static let allowlist = "orbex.utilities.allowlist"

    static func loadAllowlist() -> ActionAllowlist {
        guard let data = UserDefaults.standard.data(forKey: allowlist),
              let list = try? JSONDecoder().decode(ActionAllowlist.self, from: data) else { return .default }
        return list
    }

    static func saveAllowlist(_ list: ActionAllowlist) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: allowlist)
        }
    }
}

// MARK: - Timers

struct TimersSettingsView: View {
    @AppStorage(UtilitiesKeys.defaultTimerMinutes) private var defaultMinutes = 5
    @AppStorage(UtilitiesKeys.timerSound) private var sound = true
    @AppStorage(UtilitiesKeys.timerNotifications) private var notifications = true

    var body: some View {
        Form {
            Section("Temporizadores") {
                Stepper("Duración por defecto: \(defaultMinutes) min", value: $defaultMinutes, in: 1...180)
                Toggle("Sonar al terminar", isOn: $sound)
                Toggle("Notificación de macOS al terminar", isOn: $notifications)
            }
            Section {
                Text("Los timers sobreviven a cerrar ORBEX y a reiniciar la Mac: se guarda la hora de fin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Probá decirle al asistente: \"timer de 10 minutos para el té\" o \"pomodoro\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notas

struct NotesSettingsView: View {
    @AppStorage(UtilitiesKeys.notesDestination) private var destination = "markdown"
    @AppStorage(UtilitiesKeys.notesFolder) private var folder = "~/Documents/ORBEX Notas"

    var body: some View {
        Form {
            Section("¿Dónde guardo las notas?") {
                Picker("Destino", selection: $destination) {
                    Text("Carpeta de archivos Markdown").tag("markdown")
                    Text("Apple Notas").tag("appleNotes")
                }
                .pickerStyle(.radioGroup)
                if destination == "markdown" {
                    HStack {
                        Text(folder).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Elegir…") { chooseFolder() }
                        Button("Abrir") {
                            let path = (folder as NSString).expandingTildeInPath
                            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                } else {
                    Text("La primera vez macOS te pide permiso para que ORBEX controle Notas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Decile al asistente: \"anotá que mañana llamo al contador\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url {
            folder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

// MARK: - Acciones y apps permitidas

struct ActionsSettingsView: View {
    @State private var list = UtilitiesKeys.loadAllowlist()
    @State private var newApp = ""

    var body: some View {
        Form {
            Section("Apps que se abren sin preguntar") {
                Toggle("Apps comunes (navegadores, Mail, Spotify, Terminal, Slack…)", isOn: $list.allowCommonApps)
                ForEach(list.extraApps, id: \.self) { app in
                    HStack {
                        Text(app)
                        Spacer()
                        Button(role: .destructive) {
                            list.extraApps.removeAll { $0 == app }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Agregar app (ej. Figma)", text: $newApp)
                        .onSubmit(addApp)
                    Button("Agregar", action: addApp)
                        .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Cualquier otra app pide confirmación. Llavero y Utilidad de Discos nunca se abren solos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Acciones con nombre") {
                ForEach($list.actions) { $action in
                    ActionEditor(action: $action) {
                        list.actions.removeAll { $0.id == action.id }
                    }
                }
                Button {
                    list.actions.append(AllowedAction(name: "Nueva acción"))
                } label: {
                    Label("Nueva acción", systemImage: "plus")
                }
                Text("Ejemplo: \"setup de trabajo\" → Slack + Figma + ~/Proyectos. Decile: \"abrime mi setup de trabajo\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: list) { _, newValue in UtilitiesKeys.saveAllowlist(newValue) }
    }

    private func addApp() {
        let name = newApp.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !list.extraApps.contains(name) else { return }
        list.extraApps.append(name)
        newApp = ""
    }
}

private struct ActionEditor: View {
    @Binding var action: AllowedAction
    var onDelete: () -> Void
    @State private var newKind: ActionItem.Kind = .app
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Nombre", text: $action.name)
                    .font(.headline)
                Button("Probar") { AppLauncher.run(action) }
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            ForEach(action.items) { item in
                HStack {
                    Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                    Text(item.value)
                    Spacer()
                    Button {
                        action.items.removeAll { $0.id == item.id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Picker("", selection: $newKind) {
                    ForEach(ActionItem.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
                TextField(placeholder, text: $newValue)
                    .onSubmit(addItem)
                Button("Agregar", action: addItem)
                    .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private var placeholder: String {
        switch newKind {
        case .app: return "Nombre de la app"
        case .folder: return "~/Carpeta"
        case .url: return "sitio.com"
        }
    }

    private func addItem() {
        let v = newValue.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        action.items.append(ActionItem(kind: newKind, value: v))
        newValue = ""
    }
}
