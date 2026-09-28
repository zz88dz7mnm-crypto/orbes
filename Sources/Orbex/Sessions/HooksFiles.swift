import Foundation
import OrbexCore

/// Errores al instalar/desinstalar hooks.
enum HooksFileError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let p): return "No pude leer \(p): no es un JSON válido. No lo toqué."
        case .writeFailed(let e): return "No pude guardar los cambios: \(e)"
        }
    }
}

/// Operaciones de archivo compartidas: leer JSON, backup con fecha, escritura atómica.
private enum JSONSettingsFile {
    static func read(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HooksFileError.unreadable(url.path)
        }
        return obj
    }

    static func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func backup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".bak-" + f.string(from: Date()))
        try? FileManager.default.copyItem(at: url, to: dest)
    }

    static func write(_ obj: [String: Any], to url: URL) throws {
        let text = HooksInstaller.prettyJSON(obj) + "\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HooksFileError.writeFailed(error.localizedDescription)
        }
    }
}

/// Comando que Claude Code ejecuta (ruta estable del relé, entre comillas por los espacios).
private var hookCommand: String {
    "\"" + AppPaths.hookBinaryPath.replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// Hooks de Claude Code en `~/.claude/settings.json`: nunca se pisa el archivo; backup con fecha,
/// merge, diff para confirmar y escritura atómica (CLAUDE.md, regla 11).
enum ClaudeHooksFile {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var isInstalled: Bool {
        HooksInstaller.isInstalled(in: (try? JSONSettingsFile.read(url)) ?? nil)
    }

    /// Lo que hay hoy, cómo quedaría y el diff para mostrar antes de escribir.
    static func preview() -> (old: String, new: String, diff: String) {
        let current = (try? JSONSettingsFile.read(url)) ?? nil
        let old = current.map(HooksInstaller.prettyJSON) ?? ""
        let new = HooksInstaller.prettyJSON(HooksInstaller.install(into: current, command: hookCommand))
        return (old, new, HooksInstaller.diff(old: old, new: new))
    }

    static func install() throws {
        let current = try JSONSettingsFile.read(url)
        JSONSettingsFile.backup(url)
        try JSONSettingsFile.write(HooksInstaller.install(into: current, command: hookCommand), to: url)
    }

    static func uninstall() throws {
        guard let current = try JSONSettingsFile.read(url), HooksInstaller.isInstalled(in: current) else { return }
        JSONSettingsFile.backup(url)
        try JSONSettingsFile.write(HooksInstaller.uninstall(from: current), to: url)
    }
}

/// Hooks de Codex CLI en `~/.codex/hooks.json` (experimental, [A validar]).
enum CodexHooksFile {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    static var isInstalled: Bool {
        CodexHooksInstaller.isInstalled(in: (try? JSONSettingsFile.read(url)) ?? nil)
    }

    static func preview() -> (old: String, new: String, diff: String) {
        let current = (try? JSONSettingsFile.read(url)) ?? nil
        let old = current.map(HooksInstaller.prettyJSON) ?? ""
        let new = HooksInstaller.prettyJSON(CodexHooksInstaller.install(into: current, command: hookCommand))
        return (old, new, HooksInstaller.diff(old: old, new: new))
    }

    static func install() throws {
        let current = try JSONSettingsFile.read(url)
        JSONSettingsFile.backup(url)
        try JSONSettingsFile.write(CodexHooksInstaller.install(into: current, command: hookCommand), to: url)
    }

    static func uninstall() throws {
        guard let current = try JSONSettingsFile.read(url), CodexHooksInstaller.isInstalled(in: current) else { return }
        JSONSettingsFile.backup(url)
        try JSONSettingsFile.write(CodexHooksInstaller.uninstall(from: current), to: url)
    }
}
