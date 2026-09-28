import Foundation

// Lector del NDJSON de `claude -p --output-format stream-json --verbose --include-partial-messages`.
//
// Formas verificadas contra Claude Code 2.1.x (binario + docs "Run Claude Code programmatically"):
//   {"type":"system","subtype":"init","session_id":"…","model":"…","cwd":"…","tools":[…],"permissionMode":"…"}
//   {"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"retry_delay_ms":500,"error":"rate_limit",…}
//   {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Ho"}},…}
//   {"type":"assistant","message":{"id":"msg_…","model":"…","content":[{"type":"text","text":"…"},
//        {"type":"tool_use","id":"toolu_…","name":"Read","input":{…}}]},"session_id":"…","error":"authentication_failed"?}
//   {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_…","content":…,"is_error":false}]}}
//   {"type":"result","subtype":"success"|"error_during_execution"|"error_max_turns"|"error_max_budget_usd",
//        "is_error":false,"result":"…","session_id":"…","total_cost_usd":0.01,"duration_ms":1234,"num_turns":1,"errors":[…]}
// Todo lo demás (líneas vacías, basura, tipos nuevos) se tolera.

/// Mensaje completo de Claude (un bloque o varios).
public struct ClaudeAssistantMessage: Equatable, Sendable {
    public struct ToolUse: Equatable, Sendable {
        public var id: String
        public var name: String
        public var summary: String
        public init(id: String, name: String, summary: String) {
            self.id = id
            self.name = name
            self.summary = summary
        }
    }

    public var id: String?
    public var model: String?
    /// Textos de los bloques `text`, en orden.
    public var texts: [String]
    public var toolUses: [ToolUse]
    /// `true` si el mensaje traía razonamiento (`thinking`).
    public var hasThinking: Bool
    /// Categoría de error del CLI (`authentication_failed`, `rate_limit`, `billing_error`, …).
    public var error: String?
    /// Id de la herramienta que lanzó este mensaje (subagentes); `nil` = conversación principal.
    public var parentToolUseID: String?

    public init(id: String? = nil, model: String? = nil, texts: [String] = [], toolUses: [ToolUse] = [],
                hasThinking: Bool = false, error: String? = nil, parentToolUseID: String? = nil) {
        self.id = id
        self.model = model
        self.texts = texts
        self.toolUses = toolUses
        self.hasThinking = hasThinking
        self.error = error
        self.parentToolUseID = parentToolUseID
    }

    public var joinedText: String { texts.joined(separator: "\n\n") }
}

/// Resultado de una herramienta (viene en un mensaje `user`).
public struct ClaudeToolResult: Equatable, Sendable {
    public var toolUseID: String
    public var isError: Bool
    public init(toolUseID: String, isError: Bool) {
        self.toolUseID = toolUseID
        self.isError = isError
    }
}

/// Mensaje final (`type: "result"`).
public struct ClaudeResult: Equatable, Sendable {
    public var subtype: String
    public var isError: Bool
    public var text: String?
    public var sessionID: String?
    public var costUSD: Double?
    public var durationMs: Int?
    public var numTurns: Int?
    public var errors: [String]

    public init(subtype: String = "success", isError: Bool = false, text: String? = nil, sessionID: String? = nil,
                costUSD: Double? = nil, durationMs: Int? = nil, numTurns: Int? = nil, errors: [String] = []) {
        self.subtype = subtype
        self.isError = isError
        self.text = text
        self.sessionID = sessionID
        self.costUSD = costUSD
        self.durationMs = durationMs
        self.numTurns = numTurns
        self.errors = errors
    }

    public var succeeded: Bool { subtype == "success" && !isError }
}

/// Eventos tipados que salen del CLI.
public enum ClaudeStreamEvent: Equatable, Sendable {
    /// `system/init`: sesión lista.
    case sessionStarted(sessionID: String?, model: String?)
    /// `system/api_retry`: el CLI reintenta.
    case retrying(attempt: Int, maxRetries: Int?, error: String?)
    /// Empieza un mensaje nuevo de Claude (streaming parcial).
    case messageStarted(id: String?)
    /// Empieza un bloque de texto (para separar párrafos entre bloques).
    case textBlockStarted
    /// Pedacito de texto (streaming parcial).
    case textDelta(String)
    /// Claude está razonando (streaming parcial).
    case thinking
    /// Empieza a usar una herramienta (streaming parcial; la entrada llega completa después).
    case toolUseStarted(id: String, name: String)
    /// Mensaje completo de Claude.
    case assistant(ClaudeAssistantMessage)
    /// Resultado de una herramienta.
    case toolResult(ClaudeToolResult)
    /// Fin de la respuesta.
    case result(ClaudeResult)
    /// Línea que no es JSON (avisos del CLI, basura): se guarda para diagnosticar errores.
    case nonJSON(String)
    /// JSON válido de un tipo que no nos interesa.
    case ignored(type: String)
}

/// Parser incremental: recibe bytes en cualquier corte y devuelve eventos por cada línea completa.
public struct ClaudeStreamParser: Sendable {
    private var buffer = Data()
    /// Tope de una línea sin salto (protección contra salidas raras): 8 MB.
    public var maxLineBytes = 8 * 1024 * 1024

    public init() {}

    /// Agrega bytes leídos de stdout y devuelve los eventos de las líneas que se completaron.
    public mutating func feed(_ data: Data) -> [ClaudeStreamEvent] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        var events: [ClaudeStreamEvent] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            events.append(contentsOf: Self.parse(lineData: lineData))
        }
        if buffer.count > maxLineBytes {
            // Línea gigante sin fin: se descarta para no crecer sin límite.
            buffer.removeAll(keepingCapacity: false)
            events.append(.nonJSON("(línea demasiado larga descartada)"))
        }
        return events
    }

    /// Agrega texto (comodidad para pruebas).
    public mutating func feed(_ text: String) -> [ClaudeStreamEvent] {
        feed(Data(text.utf8))
    }

    /// Procesa lo que quedó sin salto de línea final (al terminar el proceso).
    public mutating func finish() -> [ClaudeStreamEvent] {
        defer { buffer.removeAll() }
        guard !buffer.isEmpty else { return [] }
        return Self.parse(lineData: buffer)
    }

    // MARK: - Una línea

    public static func parse(lineData: Data) -> [ClaudeStreamEvent] {
        var data = lineData
        if data.last == 0x0D { data.removeLast() } // \r\n
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return parse(line: trimmed)
    }

    public static func parse(line: String) -> [ClaudeStreamEvent] {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        guard text.first == "{",
              let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let json = obj as? [String: Any] else {
            return [.nonJSON(text.count > 2000 ? String(text.prefix(2000)) : text)]
        }
        let type = json["type"] as? String ?? ""
        switch type {
        case "system":
            return parseSystem(json)
        case "stream_event":
            return parseStreamEvent(json)
        case "assistant":
            return parseAssistant(json)
        case "user":
            return parseUser(json)
        case "result":
            return [.result(parseResult(json))]
        default:
            return [.ignored(type: type)]
        }
    }

    // MARK: - Tipos

    private static func parseSystem(_ json: [String: Any]) -> [ClaudeStreamEvent] {
        let subtype = json["subtype"] as? String ?? ""
        switch subtype {
        case "init":
            return [.sessionStarted(sessionID: json["session_id"] as? String, model: json["model"] as? String)]
        case "api_retry":
            return [.retrying(attempt: intValue(json["attempt"]) ?? 1,
                              maxRetries: intValue(json["max_retries"]),
                              error: json["error"] as? String)]
        default:
            return [.ignored(type: "system/" + subtype)]
        }
    }

    private static func parseStreamEvent(_ json: [String: Any]) -> [ClaudeStreamEvent] {
        // Los subagentes no se muestran como texto de la respuesta.
        if let parent = json["parent_tool_use_id"] as? String, !parent.isEmpty { return [.ignored(type: "stream_event/subagent")] }
        guard let event = json["event"] as? [String: Any] else { return [.ignored(type: "stream_event")] }
        let etype = event["type"] as? String ?? ""
        switch etype {
        case "message_start":
            let msg = event["message"] as? [String: Any]
            return [.messageStarted(id: msg?["id"] as? String)]
        case "content_block_start":
            guard let block = event["content_block"] as? [String: Any] else { return [] }
            switch block["type"] as? String {
            case "text":
                var out: [ClaudeStreamEvent] = [.textBlockStarted]
                if let t = block["text"] as? String, !t.isEmpty { out.append(.textDelta(t)) }
                return out
            case "tool_use", "server_tool_use":
                let id = block["id"] as? String ?? UUID().uuidString
                return [.toolUseStarted(id: id, name: block["name"] as? String ?? "herramienta")]
            case "thinking", "redacted_thinking":
                return [.thinking]
            default:
                return []
            }
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                if let t = delta["text"] as? String, !t.isEmpty { return [.textDelta(t)] }
                return []
            case "thinking_delta":
                return [.thinking]
            default:
                return []
            }
        default:
            return []
        }
    }

    private static func parseAssistant(_ json: [String: Any]) -> [ClaudeStreamEvent] {
        let message = json["message"] as? [String: Any] ?? [:]
        var out = ClaudeAssistantMessage(id: message["id"] as? String,
                                         model: message["model"] as? String,
                                         error: json["error"] as? String,
                                         parentToolUseID: json["parent_tool_use_id"] as? String)
        if let content = message["content"] as? [[String: Any]] {
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let t = block["text"] as? String { out.texts.append(t) }
                case "tool_use", "server_tool_use":
                    let name = block["name"] as? String ?? "herramienta"
                    let input = block["input"] as? [String: Any] ?? [:]
                    out.toolUses.append(.init(id: block["id"] as? String ?? UUID().uuidString,
                                              name: name,
                                              summary: ToolLabels.summary(for: name, input: input)))
                case "thinking", "redacted_thinking":
                    out.hasThinking = true
                default:
                    break
                }
            }
        } else if let s = message["content"] as? String {
            out.texts.append(s)
        }
        return [.assistant(out)]
    }

    private static func parseUser(_ json: [String: Any]) -> [ClaudeStreamEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return [.ignored(type: "user")] }
        var out: [ClaudeStreamEvent] = []
        for block in content where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String else { continue }
            out.append(.toolResult(ClaudeToolResult(toolUseID: id, isError: block["is_error"] as? Bool ?? false)))
        }
        return out.isEmpty ? [.ignored(type: "user")] : out
    }

    private static func parseResult(_ json: [String: Any]) -> ClaudeResult {
        var errors: [String] = []
        if let list = json["errors"] as? [Any] {
            for e in list {
                if let s = e as? String { errors.append(s) }
                else if let d = e as? [String: Any], let m = d["message"] as? String { errors.append(m) }
            }
        }
        let subtype = json["subtype"] as? String ?? "success"
        return ClaudeResult(subtype: subtype,
                            isError: json["is_error"] as? Bool ?? (subtype != "success"),
                            text: json["result"] as? String,
                            sessionID: json["session_id"] as? String,
                            costUSD: doubleValue(json["total_cost_usd"]),
                            durationMs: intValue(json["duration_ms"]),
                            numTurns: intValue(json["num_turns"]),
                            errors: errors)
    }

    // MARK: - Números tolerantes (JSONSerialization da NSNumber, Int o Double según la plataforma)

    static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let d as Double: return d.isFinite ? Int(d) : nil
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
