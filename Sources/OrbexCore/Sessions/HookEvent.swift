import Foundation

/// Tipo de evento de hook (Claude Code / Codex). Los nombres "oficiales" son
/// `SessionStart`, `PreToolUse`, etc.; ver `hookName`.
public enum HookEventKind: String, Sendable, CaseIterable {
    case sessionStart, sessionEnd, userPromptSubmit, preToolUse, postToolUse, postToolUseFailure,
         permissionRequest, notification, stop, stopFailure, subagentStart, subagentStop, unknown

    /// Desde el nombre que manda la herramienta ("PreToolUse" → `.preToolUse`).
    public init(hookName: String) {
        guard let first = hookName.first else { self = .unknown; return }
        let camel = first.lowercased() + hookName.dropFirst()
        self = HookEventKind(rawValue: camel) ?? .unknown
    }

    /// Nombre tal como aparece en `settings.json` ("PreToolUse").
    public var hookName: String {
        guard let first = rawValue.first else { return rawValue }
        return first.uppercased() + rawValue.dropFirst()
    }
}

/// De qué herramienta viene la sesión.
public enum SessionSource: String, Sendable {
    case claude, codex
}

/// Un evento recibido del relé `orbex-hook` (JSON de Claude Code + datos de la terminal).
public struct HookEvent: Sendable {
    public var kind: HookEventKind
    public var sessionID: String
    public var cwd: String
    public var toolName: String?
    /// Argumento principal de la herramienta: comando, ruta completa, patrón, pregunta…
    public var toolInputSummary: String?
    public var message: String?
    public var prompt: String?
    public var termProgram: String?
    public var tty: String?
    public var bundleID: String?
    public var itermSessionID: String?
    public var source: SessionSource
    /// Nombre crudo del evento ("PreToolUse", o uno que ORBEX no conoce).
    public var rawEventName: String
    /// `notification_type` de los eventos Notification (p. ej. "permission_prompt").
    public var notificationType: String?
    /// Opciones de respuesta cuando la herramienta es `AskUserQuestion`.
    public var questionOptions: [String]

    public init(kind: HookEventKind,
                sessionID: String,
                cwd: String = "",
                toolName: String? = nil,
                toolInputSummary: String? = nil,
                message: String? = nil,
                prompt: String? = nil,
                termProgram: String? = nil,
                tty: String? = nil,
                bundleID: String? = nil,
                itermSessionID: String? = nil,
                source: SessionSource = .claude,
                rawEventName: String? = nil,
                notificationType: String? = nil,
                questionOptions: [String] = []) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.toolInputSummary = toolInputSummary
        self.message = message
        self.prompt = prompt
        self.termProgram = termProgram
        self.tty = tty
        self.bundleID = bundleID
        self.itermSessionID = itermSessionID
        self.source = source
        self.rawEventName = rawEventName ?? kind.hookName
        self.notificationType = notificationType
        self.questionOptions = questionOptions
    }

    // MARK: - Texto para la isla

    /// Nombre del proyecto: la última carpeta del directorio de trabajo.
    public var projectName: String {
        let name = Self.lastComponent(cwd)
        if name.isEmpty { return source == .codex ? "Codex" : "Sesión" }
        return name
    }

    /// Descripción corta del paso, en castellano ("Lee main.swift", "Ejecuta `swift build`").
    public var stepDescription: String {
        switch kind {
        case .sessionStart: return "Sesión iniciada"
        case .sessionEnd: return "Sesión cerrada"
        case .userPromptSubmit:
            if let p = Self.oneLine(prompt, max: 70), !p.isEmpty { return "Pedido: \(p)" }
            return "Nuevo pedido"
        case .preToolUse, .postToolUse, .permissionRequest:
            return toolDescription
        case .postToolUseFailure:
            return "Falló: \(toolDescription)"
        case .notification:
            if let m = Self.oneLine(message, max: 80), !m.isEmpty { return m }
            return "Aviso"
        case .stop: return "Listo"
        case .stopFailure:
            if let m = Self.oneLine(message, max: 70), !m.isEmpty { return "Error: \(m)" }
            return "Se detuvo por un error"
        case .subagentStart: return "Subagente en marcha"
        case .subagentStop: return "Subagente terminó"
        case .unknown: return rawEventName.isEmpty ? "Evento" : rawEventName
        }
    }

    /// ¿Es una pregunta al usuario (y no un permiso común)?
    public var isQuestion: Bool {
        toolName == "AskUserQuestion"
    }

    private var toolDescription: String {
        let tool = toolName ?? ""
        let arg = toolInputSummary ?? ""
        let file = Self.lastComponent(arg)
        let short = Self.oneLine(arg, max: 60) ?? ""
        switch tool {
        case "Read": return arg.isEmpty ? "Lee un archivo" : "Lee \(file)"
        case "Edit", "MultiEdit", "NotebookEdit": return arg.isEmpty ? "Edita un archivo" : "Edita \(file)"
        case "Write": return arg.isEmpty ? "Escribe un archivo" : "Escribe \(file)"
        case "Bash", "shell", "exec_command", "local_shell":
            return short.isEmpty ? "Ejecuta un comando" : "Ejecuta `\(short)`"
        case "Grep": return short.isEmpty ? "Busca en el código" : "Busca \"\(short)\""
        case "Glob": return short.isEmpty ? "Busca archivos" : "Busca archivos \"\(short)\""
        case "LS": return arg.isEmpty ? "Lista una carpeta" : "Lista \(file)"
        case "WebFetch":
            if let host = URL(string: arg)?.host { return "Abre \(host)" }
            return "Abre una página"
        case "WebSearch": return short.isEmpty ? "Busca en la web" : "Busca en la web \"\(short)\""
        case "Task", "Agent": return short.isEmpty ? "Delega a un subagente" : "Delega: \(short)"
        case "TodoWrite": return "Actualiza la lista de tareas"
        case "AskUserQuestion": return short.isEmpty ? "Tiene una pregunta" : "Pregunta: \(short)"
        case "ExitPlanMode": return "Propone un plan"
        case "apply_patch": return "Aplica cambios"
        case "":
            return "Trabajando"
        default:
            if tool.hasPrefix("mcp__") {
                // mcp__servidor__herramienta
                let parts = tool.components(separatedBy: "__")
                if parts.count >= 3 { return "Usa \(parts[1]) · \(parts[2...].joined(separator: "__"))" }
            }
            return short.isEmpty ? "Usa \(tool)" : "Usa \(tool): \(short)"
        }
    }

    /// Último componente de una ruta ("/a/b/main.swift" → "main.swift").
    static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    /// Primera línea, recortada con "…".
    static func oneLine(_ text: String?, max: Int) -> String? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let clean = lines.first ?? ""
        if clean.count > max { return String(clean.prefix(max - 1)) + "…" }
        return lines.count > 1 ? clean + " …" : clean
    }

    // MARK: - Lectura

    /// Interpreta una línea JSON del relé. `nil` si no es un evento válido.
    public static func parse(_ data: Data) -> HookEvent? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let name = (obj["hook_event_name"] as? String) ?? (obj["hookEventName"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let sessionID = (obj["session_id"] as? String)
            ?? (obj["sessionId"] as? String)
            ?? (obj["thread_id"] as? String)
            ?? ""
        guard !sessionID.isEmpty else { return nil }

        let source = SessionSource(rawValue: (obj["source"] as? String) ?? "") ?? .claude
        let toolName = obj["tool_name"] as? String
        let input = obj["tool_input"] as? [String: Any]

        var event = HookEvent(
            kind: HookEventKind(hookName: name),
            sessionID: sessionID,
            cwd: (obj["cwd"] as? String) ?? "",
            toolName: toolName,
            toolInputSummary: input.flatMap { summarize(tool: toolName, input: $0) },
            message: (obj["message"] as? String) ?? (obj["error"] as? String),
            prompt: obj["prompt"] as? String,
            termProgram: nonEmpty(obj["term_program"]),
            tty: nonEmpty(obj["tty"]),
            bundleID: nonEmpty(obj["bundle_id"]),
            itermSessionID: nonEmpty(obj["iterm_session_id"]),
            source: source,
            rawEventName: name,
            notificationType: obj["notification_type"] as? String
        )
        if toolName == "AskUserQuestion", let input {
            event.questionOptions = questionOptions(input)
        }
        return event
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    /// El argumento más útil de cada herramienta (recortado a 500 caracteres).
    static func summarize(tool: String?, input: [String: Any]) -> String? {
        func str(_ key: String) -> String? {
            if let s = input[key] as? String, !s.isEmpty { return s }
            if let arr = input[key] as? [String], !arr.isEmpty { return arr.joined(separator: " ") }
            return nil
        }
        var value: String?
        if tool == "AskUserQuestion",
           let questions = input["questions"] as? [[String: Any]],
           let q = questions.first?["question"] as? String {
            value = q
        } else {
            for key in ["command", "cmd", "file_path", "notebook_path", "path", "pattern", "query", "url", "description", "prompt", "plan"] {
                if let s = str(key) { value = s; break }
            }
        }
        guard let v = value else { return nil }
        return v.count > 500 ? String(v.prefix(499)) + "…" : v
    }

    private static func questionOptions(_ input: [String: Any]) -> [String] {
        guard let questions = input["questions"] as? [[String: Any]],
              let options = questions.first?["options"] as? [Any] else { return [] }
        return options.compactMap { item in
            if let s = item as? String { return s }
            if let d = item as? [String: Any] { return d["label"] as? String }
            return nil
        }
    }
}
