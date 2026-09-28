import Foundation

/// Quién escribió un mensaje del chat del asistente.
public enum ChatRole: String, Codable, Sendable, CaseIterable {
    /// El usuario.
    case user
    /// Claude (respuesta del CLI `claude`).
    case assistant
    /// ORBEX mismo (comandos locales, avisos, errores).
    case system
    /// Solo actividad de herramientas (sin texto propio).
    case tool
}

/// Estado de una herramienta que usó Claude mientras respondía.
public enum ToolChipState: String, Codable, Sendable {
    case running, done, failed
}

/// "Chip" que muestra qué herramienta está usando Claude ("Leyendo archivo…").
public struct ToolChip: Identifiable, Codable, Equatable, Sendable {
    /// Id del `tool_use` de Claude (o uno generado).
    public var id: String
    /// Nombre técnico de la herramienta (`Read`, `Bash`, …).
    public var name: String
    /// Resumen corto de la entrada (ruta, comando, búsqueda…).
    public var summary: String
    public var state: ToolChipState

    public init(id: String, name: String, summary: String = "", state: ToolChipState = .running) {
        self.id = id
        self.name = name
        self.summary = summary
        self.state = state
    }

    /// Texto para mostrar: "Leyendo archivo… notas.txt".
    public var title: String {
        let base = ToolLabels.label(for: name, running: state == .running)
        return summary.isEmpty ? base : "\(base) \(summary)"
    }
}

/// Un adjunto enviado junto a un mensaje (solo se guarda el nombre y el tamaño).
public struct ChatAttachmentInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var bytes: Int

    public init(name: String, bytes: Int) {
        self.name = name
        self.bytes = bytes
    }
}

/// Un mensaje del chat del asistente.
public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var toolChips: [ToolChip]
    public var date: Date
    /// `true` mientras llegan tokens (muestra el cursor titilando).
    public var isStreaming: Bool
    /// Mensaje de error (se pinta distinto y ofrece reintentar).
    public var isError: Bool
    /// Respuesta de ORBEX que espera "Confirmar / Cancelar".
    public var needsConfirmation: Bool
    public var attachments: [ChatAttachmentInfo]
    /// Costo estimado que informa el CLI (con suscripción es solo una estimación).
    public var costUSD: Double?
    /// Duración total de la respuesta en milisegundos.
    public var durationMs: Int?
    /// Modelo que respondió (si el CLI lo informó).
    public var model: String?

    public init(id: UUID = UUID(),
                role: ChatRole,
                text: String,
                toolChips: [ToolChip] = [],
                date: Date = Date(),
                isStreaming: Bool = false,
                isError: Bool = false,
                needsConfirmation: Bool = false,
                attachments: [ChatAttachmentInfo] = [],
                costUSD: Double? = nil,
                durationMs: Int? = nil,
                model: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.toolChips = toolChips
        self.date = date
        self.isStreaming = isStreaming
        self.isError = isError
        self.needsConfirmation = needsConfirmation
        self.attachments = attachments
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.model = model
    }

    /// Nota chiquita al pie: "3,2 s · ≈ US$ 0,012".
    public var footnote: String? {
        var parts: [String] = []
        if let ms = durationMs, ms > 0 {
            let s = Double(ms) / 1000
            parts.append(s < 10 ? String(format: "%.1f s", s).replacingOccurrences(of: ".", with: ",")
                                : "\(Int(s.rounded())) s")
        }
        if let c = costUSD, c > 0 {
            let txt = c < 0.01 ? String(format: "%.4f", c) : String(format: "%.3f", c)
            parts.append("≈ US$ " + txt.replacingOccurrences(of: ".", with: ","))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Conversación guardada en disco (JSON) para retomarla al volver a abrir ORBEX.
public struct ChatTranscript: Codable, Equatable, Sendable {
    public var version: Int
    /// Sesión del CLI para `--resume`.
    public var sessionID: String?
    public var messages: [ChatMessage]

    public init(sessionID: String?, messages: [ChatMessage], version: Int = 1) {
        self.version = version
        self.sessionID = sessionID
        self.messages = messages
    }

    /// Deja solo los últimos `max` mensajes; nada queda "en streaming" ni esperando confirmación.
    public func trimmed(max: Int) -> ChatTranscript {
        var copy = self
        let keep = Swift.max(0, max)
        if copy.messages.count > keep { copy.messages = Array(copy.messages.suffix(keep)) }
        for i in copy.messages.indices {
            copy.messages[i].isStreaming = false
            copy.messages[i].needsConfirmation = false
            for j in copy.messages[i].toolChips.indices where copy.messages[i].toolChips[j].state == .running {
                copy.messages[i].toolChips[j].state = .done
            }
        }
        return copy
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(self)
    }

    public static func decode(_ data: Data) throws -> ChatTranscript {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(ChatTranscript.self, from: data)
    }
}

/// Nombres en castellano de las herramientas de Claude Code.
public enum ToolLabels {
    public static func label(for tool: String, running: Bool = true) -> String {
        let base: String
        switch tool {
        case "Read": base = running ? "Leyendo archivo" : "Leyó archivo"
        case "Write": base = running ? "Escribiendo archivo" : "Escribió archivo"
        case "Edit", "MultiEdit", "NotebookEdit": base = running ? "Editando archivo" : "Editó archivo"
        case "Bash", "BashOutput", "PowerShell": base = running ? "Ejecutando comando" : "Ejecutó comando"
        case "Grep", "Glob", "LS": base = running ? "Buscando" : "Buscó"
        case "WebFetch": base = running ? "Leyendo la web" : "Leyó la web"
        case "WebSearch": base = running ? "Buscando en la web" : "Buscó en la web"
        case "Task", "Agent": base = running ? "Delegando" : "Delegó"
        case "TodoWrite": base = running ? "Organizando tareas" : "Organizó tareas"
        case "Skill": base = running ? "Usando habilidad" : "Usó habilidad"
        default:
            if tool.hasPrefix("mcp__") {
                let short = tool.split(separator: "_", omittingEmptySubsequences: true).last.map(String.init) ?? tool
                base = running ? "Usando \(short)" : "Usó \(short)"
            } else {
                base = running ? "Usando \(tool)" : "Usó \(tool)"
            }
        }
        return running ? base + "…" : base
    }

    /// Resumen corto de la entrada de una herramienta (ruta, comando, patrón o URL).
    public static func summary(for tool: String, input: [String: Any]) -> String {
        let keys = ["file_path", "notebook_path", "path", "command", "pattern", "url", "query", "description", "prompt"]
        for k in keys {
            if let v = input[k] as? String, !v.isEmpty {
                var s = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if k.hasSuffix("path") { s = (s as NSString).lastPathComponent }
                s = s.replacingOccurrences(of: "\n", with: " ")
                return s.count > 48 ? String(s.prefix(47)) + "…" : s
            }
        }
        return ""
    }
}
