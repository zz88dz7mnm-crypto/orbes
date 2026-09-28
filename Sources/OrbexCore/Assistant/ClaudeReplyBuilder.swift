import Foundation

/// Arma la respuesta visible a partir de los eventos del CLI.
///
/// Con `--include-partial-messages` el texto llega dos veces: en pedacitos (`textDelta`) y después
/// completo (`assistant`). Este armador no duplica: por cada mensaje de Claude se queda con la
/// versión más larga (la parcial mientras llega, la completa si faltaron parciales).
public struct ClaudeReplyBuilder: Sendable {
    public private(set) var sessionID: String?
    public private(set) var model: String?
    public private(set) var toolChips: [ToolChip] = []
    /// Claude está razonando (todavía sin texto nuevo).
    public private(set) var isThinking = false
    public private(set) var result: ClaudeResult?
    /// Categoría de error que el CLI adjuntó a un mensaje (`authentication_failed`, …).
    public private(set) var assistantError: String?
    /// Aviso de reintento ("Reintentando (2/10)…").
    public private(set) var retryNote: String?
    /// Líneas de stdout que no eran JSON (para diagnosticar).
    public private(set) var strayLines: [String] = []

    private var order: [String] = []
    private var streamed: [String: String] = [:]
    private var complete: [String: [String]] = [:]
    private var currentKey: String?
    private var anonCounter = 0

    public init() {}

    /// Aplica un evento. Devuelve `true` si cambió algo visible.
    @discardableResult
    public mutating func apply(_ event: ClaudeStreamEvent) -> Bool {
        switch event {
        case .sessionStarted(let sid, let m):
            if let sid, !sid.isEmpty { sessionID = sid }
            if let m, !m.isEmpty { model = m }
            return false
        case .retrying(let attempt, let maxRetries, let error):
            let total = maxRetries.map { "/\($0)" } ?? ""
            let why = error.map { " (\(ClaudeErrorClassifier.shortReason(for: $0)))" } ?? ""
            retryNote = "Reintentando \(attempt)\(total)\(why)…"
            return true
        case .messageStarted(let id):
            currentKey = key(for: id)
            retryNote = nil
            return false
        case .textBlockStarted:
            let k = currentKey ?? key(for: nil)
            currentKey = k
            if let s = streamed[k], !s.isEmpty, !s.hasSuffix("\n\n") { streamed[k] = s + "\n\n" }
            return false
        case .textDelta(let t):
            let k = currentKey ?? key(for: nil)
            currentKey = k
            streamed[k, default: ""] += t
            isThinking = false
            retryNote = nil
            return true
        case .thinking:
            let changed = !isThinking
            isThinking = true
            return changed
        case .toolUseStarted(let id, let name):
            isThinking = false
            if !toolChips.contains(where: { $0.id == id }) {
                toolChips.append(ToolChip(id: id, name: name))
                return true
            }
            return false
        case .assistant(let msg):
            if let e = msg.error, !e.isEmpty { assistantError = e }
            if let m = msg.model, !m.isEmpty, msg.parentToolUseID == nil { model = m }
            var changed = false
            for use in msg.toolUses {
                if let i = toolChips.firstIndex(where: { $0.id == use.id }) {
                    if toolChips[i].summary != use.summary { toolChips[i].summary = use.summary; changed = true }
                } else {
                    toolChips.append(ToolChip(id: use.id, name: use.name, summary: use.summary))
                    changed = true
                }
            }
            // El texto de subagentes no es parte de la respuesta.
            guard msg.parentToolUseID == nil else { return changed }
            let texts = msg.texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !texts.isEmpty {
                let k = msg.id.map { key(for: $0) } ?? (currentKey ?? key(for: nil))
                complete[k, default: []].append(contentsOf: texts)
                isThinking = false
                changed = true
            }
            return changed
        case .toolResult(let r):
            if let i = toolChips.firstIndex(where: { $0.id == r.toolUseID }) {
                toolChips[i].state = r.isError ? .failed : .done
                return true
            }
            return false
        case .result(let r):
            result = r
            if let sid = r.sessionID, !sid.isEmpty { sessionID = sid }
            for i in toolChips.indices where toolChips[i].state == .running { toolChips[i].state = .done }
            isThinking = false
            retryNote = nil
            return true
        case .nonJSON(let line):
            strayLines.append(line)
            if strayLines.count > 30 { strayLines.removeFirst(strayLines.count - 30) }
            return false
        case .ignored:
            return false
        }
    }

    /// Texto visible hasta ahora.
    public var text: String {
        var parts: [String] = []
        for k in order {
            let s = (streamed[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let c = (complete[k] ?? []).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let pick = c.count > s.count ? c : s
            if !pick.isEmpty { parts.append(pick) }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Texto final: si no llegó nada por streaming, el `result` del CLI.
    public var finalText: String {
        let t = text
        if !t.isEmpty { return t }
        if let r = result, r.succeeded, let rt = r.text?.trimmingCharacters(in: .whitespacesAndNewlines) { return rt }
        return ""
    }

    /// `true` si la respuesta terminó con error (según `result` o el error del mensaje).
    public var failed: Bool {
        if let r = result { return !r.succeeded }
        return assistantError != nil
    }

    private mutating func key(for id: String?) -> String {
        let k: String
        if let id, !id.isEmpty {
            k = id
        } else {
            anonCounter += 1
            k = "anon-\(anonCounter)"
        }
        if !order.contains(k) { order.append(k) }
        return k
    }
}

/// Qué salió mal al hablar con el CLI.
public struct ClaudeFailure: Error, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case notInstalled, notLoggedIn, usageLimit, rateLimited, overloaded, modelNotFound, outdatedCLI, cancelled, generic
    }

    public var kind: Kind
    /// Mensaje en castellano para mostrar.
    public var message: String
    /// Detalle técnico (primera línea útil del CLI).
    public var detail: String?

    public init(kind: Kind, message: String, detail: String? = nil) {
        self.kind = kind
        self.message = message
        self.detail = detail
    }

    public static let notInstalledMessage = "No encontré `claude`. Instalá Claude Code y logueate corriendo `claude` en la Terminal."

    public static func notInstalled() -> ClaudeFailure {
        ClaudeFailure(kind: .notInstalled, message: notInstalledMessage)
    }

    public static func cancelled() -> ClaudeFailure {
        ClaudeFailure(kind: .cancelled, message: "Cortaste la respuesta.")
    }

    /// Vale la pena ofrecer "Reintentar".
    public var isRetryable: Bool {
        switch kind {
        case .rateLimited, .overloaded, .generic, .cancelled: return true
        case .notInstalled, .notLoggedIn, .usageLimit, .modelNotFound, .outdatedCLI: return false
        }
    }
}

/// Traduce los errores del CLI a mensajes claros.
public enum ClaudeErrorClassifier {
    /// Clasifica un fallo a partir de todo lo que dejó el CLI.
    public static func classify(assistantError: String? = nil,
                                resultText: String? = nil,
                                errors: [String] = [],
                                stderr: String = "",
                                strayLines: [String] = [],
                                exitCode: Int32? = nil) -> ClaudeFailure {
        let pieces = [assistantError ?? "", resultText ?? ""] + errors + [stderr] + strayLines
        let all = pieces.joined(separator: "\n")
        let low = all.lowercased()
        let detail = firstUsefulLine(errors + [resultText ?? "", stderr] + strayLines)

        if exitCode == 127 || low.contains("command not found") || low.contains("claude: not found")
            || low.contains("no such file or directory: claude") {
            return .notInstalled()
        }
        if low.contains("unknown option") || low.contains("unknown argument") || low.contains("error: option '") {
            return ClaudeFailure(kind: .outdatedCLI,
                                 message: "Tu `claude` no entiende una de las opciones que usa ORBEX. Actualizalo con `claude update` en la Terminal.",
                                 detail: detail)
        }
        if assistantError == "authentication_failed" || assistantError == "oauth_org_not_allowed"
            || low.contains("not logged in") || low.contains("/login") || low.contains("invalid api key")
            || low.contains("login expired") || low.contains("authentication required")
            || low.contains("authentication_failed") || low.contains("oauth token has expired") {
            return ClaudeFailure(kind: .notLoggedIn,
                                 message: "Claude Code no tiene la sesión iniciada. Abrí la Terminal, corré `claude` y logueate con tu cuenta.",
                                 detail: detail)
        }
        if assistantError == "billing_error" || low.contains("usage limit") || low.contains("you've hit your")
            || low.contains("billing_error") || low.contains("credit balance") {
            return ClaudeFailure(kind: .usageLimit,
                                 message: "Llegaste al límite de uso de tu plan de Claude. Probá de nuevo más tarde.",
                                 detail: detail)
        }
        if assistantError == "model_not_found" || low.contains("model_not_found")
            || (low.contains("model") && (low.contains("not found") || low.contains("invalid model") || low.contains("not available"))) {
            return ClaudeFailure(kind: .modelNotFound,
                                 message: "El modelo elegido no existe o tu plan no lo incluye. Revisá Configuración › Asistente (vacío = el de siempre).",
                                 detail: detail)
        }
        if assistantError == "rate_limit" || low.contains("rate_limit") || low.contains("rate limit") {
            return ClaudeFailure(kind: .rateLimited,
                                 message: "Claude está recibiendo demasiados pedidos. Probá de nuevo en un ratito.",
                                 detail: detail)
        }
        if assistantError == "overloaded" || low.contains("overloaded") {
            return ClaudeFailure(kind: .overloaded,
                                 message: "Los servidores de Claude están saturados. Probá de nuevo en un ratito.",
                                 detail: detail)
        }
        return ClaudeFailure(kind: .generic, message: "Claude no pudo responder.", detail: detail)
    }

    /// Motivo corto para los avisos de reintento.
    public static func shortReason(for category: String) -> String {
        switch category {
        case "rate_limit": return "demasiados pedidos"
        case "overloaded": return "servidores saturados"
        case "server_error": return "error del servidor"
        case "authentication_failed": return "sin sesión"
        case "billing_error": return "límite del plan"
        default: return "error de red"
        }
    }

    static func firstUsefulLine(_ texts: [String]) -> String? {
        for t in texts {
            for raw in t.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("at ") || line.hasPrefix("{") { continue }
                return line.count > 200 ? String(line.prefix(199)) + "…" : line
            }
        }
        return nil
    }
}
