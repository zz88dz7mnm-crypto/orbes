import Foundation
import OrbexCore

/// Resultado de ejecutar un comando: texto para mostrar y si hace falta que el usuario confirme.
struct CommandResult {
    let message: String
    let needsConfirmation: Bool

    init(message: String, needsConfirmation: Bool = false) {
        self.message = message
        self.needsConfirmation = needsConfirmation
    }
}

/// Ejecuta los comandos de `CommandParser` aplicando los niveles de autonomía (informe §11.2):
/// 0–1 se hacen (1 con aviso), 2 pide confirmación, 3 nunca.
@MainActor
final class CommandExecutor {
    static let shared = CommandExecutor()

    /// `Data` con el JSON de `ActionAllowlist`.
    static let allowlistKey = "orbex.utilities.allowlist"

    private var pending: OrbexCommand?

    private init() {}

    // MARK: - Lista de acciones

    static func loadAllowlist() -> ActionAllowlist {
        guard let data = UserDefaults.standard.data(forKey: allowlistKey),
              let list = try? JSONDecoder().decode(ActionAllowlist.self, from: data) else { return .default }
        return list
    }

    static func saveAllowlist(_ list: ActionAllowlist) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: allowlistKey)
        }
    }

    var allowlist: ActionAllowlist { Self.loadAllowlist() }

    /// Hay algo esperando confirmación.
    var hasPending: Bool { pending != nil }

    // MARK: - API

    func execute(_ command: OrbexCommand) async -> CommandResult {
        let level = AutonomyPolicy.level(for: command, allowlist: allowlist)
        switch level {
        case .never:
            pending = nil
            OrbexBus.play(.permissionDenied)
            return CommandResult(message: "Eso no lo puedo hacer yo: toca credenciales o la seguridad de la Mac. Hacelo vos a mano 🙂")
        case .confirm:
            pending = command
            return CommandResult(message: "¿Querés que \(describe(command))? No está en tu lista de acciones.",
                                 needsConfirmation: true)
        case .free, .notify:
            pending = nil
            return await run(command)
        }
    }

    /// Ejecuta lo que había pedido confirmación.
    func confirmPending() async -> CommandResult {
        guard let command = pending else { return CommandResult(message: "No había nada pendiente.") }
        pending = nil
        OrbexBus.play(.permissionGranted)
        return await run(command)
    }

    func cancelPending() {
        pending = nil
    }

    /// Interpreta texto libre y ejecuta todo lo que entienda ("abrí Figma y la terminal").
    /// Devuelve `nil` si no es un comando (el texto va al asistente).
    func handle(text: String) async -> CommandResult? {
        let commands = CommandParser.parseAll(text)
        guard !commands.isEmpty else { return nil }
        var messages: [String] = []
        for command in commands {
            let result = await execute(command)
            if result.needsConfirmation { return result }
            messages.append(result.message)
        }
        return CommandResult(message: messages.joined(separator: "\n"))
    }

    // MARK: - Ejecución

    private func run(_ command: OrbexCommand) async -> CommandResult {
        switch command {
        case .openApp(let name):
            return openApp(name)
        case .openFolder(let path):
            guard let resolved = resolveFolder(path) else {
                return fail("No encontré la carpeta \"\(path)\".")
            }
            return AppLauncher.openFolder(resolved)
                ? CommandResult(message: "Abriendo \((resolved as NSString).lastPathComponent) 📂")
                : fail("No pude abrir la carpeta \"\(path)\".")
        case .note(let text):
            return CommandResult(message: await NotesStore.shared.add(text))
        case .timer(let seconds, let label):
            let t = TimersStore.shared.startTimer(seconds: seconds, label: label)
            let what = label.map { " para \($0)" } ?? ""
            return CommandResult(message: "Listo: timer de \(TimerFormat.words(t.duration))\(what) ⏱")
        case .stopwatch:
            if !TimersStore.shared.stopwatch.isRunning { TimersStore.shared.toggleStopwatch() }
            return CommandResult(message: "Cronómetro andando ⏱")
        case .pomodoro:
            TimersStore.shared.startPomodoro()
            return CommandResult(message: "Pomodoro: 25 min de foco. ¡Vamos! 🍅")
        case .remind(let date, let text):
            SchedulerStore.shared.addReminder(at: date, text: text)
            OrbexBus.play(.noteSaved)
            return CommandResult(message: "Listo, te aviso a las \(SchedulerStore.time(date)): \(text) ⏰")
        case .scheduledAction(let date, let name):
            SchedulerStore.shared.addAction(at: date, name: name)
            OrbexBus.play(.noteSaved)
            if allowlist.action(named: name) == nil {
                return CommandResult(message: "Anotado para las \(SchedulerStore.time(date)): \(name). No está en tu lista de acciones, así que a esa hora te pido confirmación.")
            }
            return CommandResult(message: "Listo, a las \(SchedulerStore.time(date)) hago \(name) ⏰")
        case .remember(let fact):
            if MemoryStore.shared.add(fact) {
                OrbexBus.play(.noteSaved)
                return CommandResult(message: "Me lo acuerdo: \(fact) 🧠")
            }
            return CommandResult(message: "Eso ya lo sabía: \(fact) 🙂")
        case .showClock:
            OrbexBus.perform("clock")
            return CommandResult(message: "Modo reloj 🕰")
        }
    }

    private func openApp(_ name: String) -> CommandResult {
        if let action = allowlist.action(named: name) {
            return runAction(action)
        }
        if AppLauncher.openApp(named: name) {
            return CommandResult(message: "Abriendo \(name) ✨")
        }
        if AutonomyPolicy.looksLikeWebAddress(name), AppLauncher.openURL(AutonomyPolicy.webURLString(name)) {
            return CommandResult(message: "Abriendo \(name) 🌐")
        }
        return fail("No encontré la app \"\(name)\" en Aplicaciones.")
    }

    private func runAction(_ action: AllowedAction) -> CommandResult {
        guard !action.items.isEmpty else {
            return CommandResult(message: "\"\(action.name)\" todavía está vacía: armala en Configuración › Acciones.")
        }
        var failed: [String] = []
        for item in action.items {
            let ok: Bool
            switch item.kind {
            case .app: ok = AppLauncher.openApp(named: item.value)
            case .folder: ok = resolveFolder(item.value).map { AppLauncher.openFolder($0) } ?? false
            case .url: ok = AppLauncher.openURL(AutonomyPolicy.webURLString(item.value))
            }
            if !ok { failed.append(item.value) }
        }
        if failed.isEmpty { return CommandResult(message: "Listo: \(action.name) ✨") }
        return fail("Abrí \(action.name), pero no pude con: \(failed.joined(separator: ", ")).")
    }

    /// Ruta absoluta de una carpeta: "~/x", "/x" o un nombre suelto que se busca en la carpeta personal.
    private func resolveFolder(_ path: String) -> String? {
        let fm = FileManager.default
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let full = (trimmed as NSString).expandingTildeInPath
            return fm.fileExists(atPath: full) ? full : nil
        }
        // Carpeta de alguna acción con ese nombre.
        let key = AppAliases.matchKey(trimmed)
        for item in allowlist.actions.flatMap({ $0.items }) where item.kind == .folder {
            let full = (item.value as NSString).expandingTildeInPath
            if AppAliases.matchKey((full as NSString).lastPathComponent) == key { return full }
        }
        let home = NSHomeDirectory()
        let bases = ["", "Documents", "Desktop", "Developer", "Projects", "Proyectos", "Documents/Proyectos", "Downloads"]
        for base in bases {
            let dir = base.isEmpty ? home : (home as NSString).appendingPathComponent(base)
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if let hit = entries.first(where: { AppAliases.matchKey($0) == key }) {
                let full = (dir as NSString).appendingPathComponent(hit)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue { return full }
            }
        }
        return nil
    }

    private func describe(_ command: OrbexCommand) -> String {
        switch command {
        case .openApp(let name): return "abra \(name)"
        case .openFolder(let path): return "abra la carpeta \(path)"
        case .note: return "guarde la nota"
        case .timer: return "ponga el timer"
        case .stopwatch: return "arranque el cronómetro"
        case .pomodoro: return "arranque el pomodoro"
        case .remind(_, let text): return "te recuerde \(text)"
        case .scheduledAction(_, let name): return "programe \(name)"
        case .remember(let fact): return "me acuerde de \(fact)"
        case .showClock: return "muestre el reloj"
        }
    }

    private func fail(_ message: String) -> CommandResult {
        OrbexBus.play(.error)
        return CommandResult(message: message)
    }
}
