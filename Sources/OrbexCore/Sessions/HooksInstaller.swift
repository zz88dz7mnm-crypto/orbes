import Foundation

/// Mezcla los hooks de ORBEX en `~/.claude/settings.json` sin tocar los hooks de otros.
/// Todo es puro (diccionarios JSON): la app hace el backup, muestra el diff y escribe.
public enum HooksInstaller {
    /// Cualquier comando que contenga esto se considera de ORBEX.
    public static let marker = "orbex-hook"

    /// Hooks viejos de Coucou / NotchBuddy (la base de ORBEX). Se quitan al instalar los de ORBEX
    /// para que no haya dos apps respondiendo el mismo permiso. Solo se quita el comando que coincide;
    /// el resto del grupo (hooks de otros) queda intacto.
    public static let legacyMarkers = ["nb-hook", "NotchBuddy", ".claude/coucou", "Coucou.app"]

    /// Eventos de Claude Code que escucha ORBEX y su timeout (segundos).
    public static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("SessionEnd", 10), ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
        ("PermissionRequest", 120), ("Notification", 10),
        ("Stop", 10), ("StopFailure", 10), ("SubagentStart", 10), ("SubagentStop", 10),
    ]

    /// Devuelve la configuración con los hooks de ORBEX agregados (reemplaza los viejos de ORBEX).
    public static func install(into settings: [String: Any]?, command: String) -> [String: Any] {
        var result = settings ?? [:]
        var hooks = uninstallHooks(removeLegacy(result["hooks"] as? [String: Any] ?? [:]))
        for event in events {
            var matchers = hooks[event.name] as? [[String: Any]] ?? []
            matchers.append(["hooks": [["type": "command", "command": command, "timeout": event.timeout]]])
            hooks[event.name] = matchers
        }
        result["hooks"] = hooks
        return result
    }

    /// Devuelve la configuración sin los hooks de ORBEX (los demás quedan intactos).
    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard let hooks = result["hooks"] as? [String: Any] else { return result }
        let cleaned = uninstallHooks(hooks)
        if cleaned.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = cleaned }
        return result
    }

    public static func isInstalled(in settings: [String: Any]?) -> Bool {
        guard let hooks = settings?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: isOrbexMatcher) ?? false
        }
    }

    /// ¿Quedan hooks viejos de Coucou / NotchBuddy?
    public static func hasLegacyHooks(in settings: [String: Any]?) -> Bool {
        guard let hooks = settings?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains { matcher in
                (matcher["hooks"] as? [[String: Any]])?.contains(where: isLegacyHook) ?? false
            } ?? false
        }
    }

    /// Devuelve la configuración sin los hooks viejos de Coucou / NotchBuddy.
    public static func removeLegacy(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard let hooks = result["hooks"] as? [String: Any] else { return result }
        let cleaned = removeLegacy(hooks)
        if cleaned.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = cleaned }
        return result
    }

    /// JSON lindo y estable (claves ordenadas) para mostrar y escribir.
    public static func prettyJSON(_ obj: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text.replacingOccurrences(of: "\\/", with: "/")
    }

    /// Diff por líneas (LCS): "+ " agregada, "- " quitada, "  " igual.
    public static func diff(old: String, new: String) -> String {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let n = a.count, m = b.count
        // Tabla LCS (archivos chicos: settings.json).
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                out.append("  " + a[i]); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                out.append("- " + a[i]); i += 1
            } else {
                out.append("+ " + b[j]); j += 1
            }
        }
        while i < n { out.append("- " + a[i]); i += 1 }
        while j < m { out.append("+ " + b[j]); j += 1 }
        return out.joined(separator: "\n")
    }

    // MARK: - Privado

    static func isOrbexMatcher(_ matcher: [String: Any]) -> Bool {
        guard let list = matcher["hooks"] as? [[String: Any]] else { return false }
        return list.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    static func isLegacyHook(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String, !command.contains(marker) else { return false }
        return legacyMarkers.contains { command.contains($0) }
    }

    /// Quita cada comando viejo; el grupo se borra solo si queda vacío.
    static func removeLegacy(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let matchers = value as? [[String: Any]] else { result[event] = value; continue }
            var kept: [[String: Any]] = []
            for var matcher in matchers {
                guard let list = matcher["hooks"] as? [[String: Any]] else { kept.append(matcher); continue }
                let filtered = list.filter { !isLegacyHook($0) }
                if filtered.count == list.count { kept.append(matcher); continue }
                if filtered.isEmpty { continue }
                matcher["hooks"] = filtered
                kept.append(matcher)
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    static func uninstallHooks(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let matchers = value as? [[String: Any]] else { result[event] = value; continue }
            let kept = matchers.filter { !isOrbexMatcher($0) }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }
}

/// Hooks de Codex CLI en `~/.codex/hooks.json`. **[A validar]**: el formato de Codex cambia seguido
/// (informe §3.4); se usa la misma forma que Claude Code con el comando `orbex-hook --codex`.
public enum CodexHooksInstaller {
    public static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("UserPromptSubmit", 10), ("PreToolUse", 10), ("PostToolUse", 10),
        ("PermissionRequest", 120), ("Stop", 10),
    ]

    public static func install(into settings: [String: Any]?, command: String) -> [String: Any] {
        var result = settings ?? [:]
        var hooks = HooksInstaller.uninstallHooks(result["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var matchers = hooks[event.name] as? [[String: Any]] ?? []
            matchers.append(["hooks": [["type": "command", "command": command + " --codex", "timeout": event.timeout]]])
            hooks[event.name] = matchers
        }
        result["hooks"] = hooks
        return result
    }

    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        HooksInstaller.uninstall(from: settings)
    }

    public static func isInstalled(in settings: [String: Any]?) -> Bool {
        HooksInstaller.isInstalled(in: settings)
    }
}

/// Respuesta de ORBEX a un `PermissionRequest` de Claude Code (una línea JSON).
public enum PermissionReply {
    public static func json(allow: Bool, message: String? = nil) -> String {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = message ?? "Denegado desde ORBEX" }
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return allow
                ? #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
                : #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denegado desde ORBEX"},"hookEventName":"PermissionRequest"}}"#
        }
        return text
    }
}
