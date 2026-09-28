import Foundation

/// En qué anda una sesión de Claude Code / Codex.
public enum SessionStatus: String, Sendable {
    case idle, thinking, working, needsPermission, question, finished, failed
}

/// Un paso visible en la isla ("Lee main.swift").
public struct SessionStep: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let date: Date

    public init(id: UUID = UUID(), text: String, date: Date) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// Estado de una sesión, armado a partir de sus eventos.
public struct SessionInfo: Sendable, Identifiable, Equatable {
    public let id: String            // = session_id
    public var project: String
    public var cwd: String
    public var status: SessionStatus
    public var steps: [SessionStep]  // los últimos 20
    public var lastUpdate: Date
    public var termProgram: String?
    public var tty: String?
    public var bundleID: String?
    public var itermSessionID: String?
    public var source: SessionSource
    /// Herramienta que está esperando permiso (si hay).
    public var pendingTool: String?

    public init(id: String, project: String, cwd: String, status: SessionStatus = .idle,
                steps: [SessionStep] = [], lastUpdate: Date, termProgram: String? = nil,
                tty: String? = nil, bundleID: String? = nil, itermSessionID: String? = nil,
                source: SessionSource = .claude, pendingTool: String? = nil) {
        self.id = id
        self.project = project
        self.cwd = cwd
        self.status = status
        self.steps = steps
        self.lastUpdate = lastUpdate
        self.termProgram = termProgram
        self.tty = tty
        self.bundleID = bundleID
        self.itermSessionID = itermSessionID
        self.source = source
        self.pendingTool = pendingTool
    }

    /// Último paso (para la línea de estado).
    public var currentStep: String? { steps.last?.text }
}

/// Qué pasó con un evento, para que la app reaccione (sonido, personaje, abrir la isla).
public enum SessionSignal: Sendable, Equatable {
    case started, step, needsPermission, question, finished, failed
}

/// Máquina de estados pura de las sesiones. Sin hilos ni temporizadores:
/// la app llama `apply` con cada evento y `tick` cada tanto.
public struct SessionTracker: Sendable {
    public static let maxSteps = 20
    /// "Terminado" vuelve a "en reposo" después de esto.
    public static let finishedLinger: TimeInterval = 6
    /// Sesiones en reposo se olvidan después de esto.
    public static let idleExpiry: TimeInterval = 30 * 60
    /// Sesiones sin noticias (la terminal se cerró sin SessionEnd) se olvidan después de esto.
    public static let staleExpiry: TimeInterval = 2 * 60 * 60

    public private(set) var sessions: [String: SessionInfo] = [:]

    public init() {}

    /// Primero las que necesitan atención, después las que trabajan, después el resto;
    /// dentro de cada grupo, la más reciente primero.
    public var sorted: [SessionInfo] {
        sessions.values.sorted { a, b in
            let pa = Self.priority(a.status), pb = Self.priority(b.status)
            if pa != pb { return pa < pb }
            if a.lastUpdate != b.lastUpdate { return a.lastUpdate > b.lastUpdate }
            return a.id < b.id
        }
    }

    public var isWorking: Bool {
        sessions.values.contains { $0.status == .working || $0.status == .thinking }
    }

    public var needsAttention: Bool {
        sessions.values.contains { $0.status == .needsPermission || $0.status == .question }
    }

    private static func priority(_ s: SessionStatus) -> Int {
        switch s {
        case .needsPermission, .question: return 0
        case .working, .thinking: return 1
        case .failed: return 2
        case .finished: return 3
        case .idle: return 4
        }
    }

    // MARK: - Eventos

    @discardableResult
    public mutating func apply(_ e: HookEvent, now: Date = Date()) -> [SessionSignal] {
        if e.kind == .sessionEnd {
            sessions[e.sessionID] = nil
            return []
        }
        var signals: [SessionSignal] = []
        var info: SessionInfo
        if let existing = sessions[e.sessionID] {
            info = existing
        } else {
            info = SessionInfo(id: e.sessionID, project: e.projectName, cwd: e.cwd,
                               lastUpdate: now, source: e.source)
            signals.append(.started)
        }

        // Datos de la sesión y de la terminal (se conservan si el evento no los trae).
        if !e.cwd.isEmpty {
            info.cwd = e.cwd
            info.project = e.projectName
        }
        if let v = e.termProgram { info.termProgram = v }
        if let v = e.tty { info.tty = v }
        if let v = e.bundleID { info.bundleID = v }
        if let v = e.itermSessionID { info.itermSessionID = v }
        info.source = e.source
        info.lastUpdate = now

        let waiting = info.status == .needsPermission || info.status == .question

        switch e.kind {
        case .sessionStart:
            info.status = .idle
            info.pendingTool = nil
            Self.addStep(&info, e.stepDescription, now)

        case .userPromptSubmit:
            info.status = .thinking
            info.pendingTool = nil
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.step)

        case .preToolUse:
            if e.isQuestion {
                info.status = .question
                info.pendingTool = e.toolName
                Self.addStep(&info, e.stepDescription, now)
                if !waiting { signals.append(.question) }
            } else {
                // Si hay un permiso pendiente, el estado no cambia (herramientas en paralelo).
                if !waiting { info.status = .working }
                Self.addStep(&info, e.stepDescription, now)
                signals.append(.step)
            }

        case .permissionRequest:
            let text = e.stepDescription
            let newStatus: SessionStatus = e.isQuestion ? .question : .needsPermission
            // Idempotente: el mismo pedido dos veces no vuelve a avisar.
            let repeated = info.status == newStatus && info.pendingTool == e.toolName
                && info.steps.last?.text == text
            info.status = newStatus
            info.pendingTool = e.toolName
            if info.steps.last?.text != text { Self.addStep(&info, text, now) }
            if !repeated { signals.append(e.isQuestion ? .question : .needsPermission) }

        case .postToolUse:
            if waiting {
                // Se resolvió el permiso (o la pregunta) de esta herramienta.
                if info.pendingTool == nil || info.pendingTool == e.toolName {
                    info.status = .working
                    info.pendingTool = nil
                }
            } else if info.status != .finished && info.status != .failed {
                info.status = .working
            }

        case .postToolUseFailure:
            if waiting && (info.pendingTool == nil || info.pendingTool == e.toolName) {
                info.pendingTool = nil
                info.status = .working
            } else if !waiting {
                info.status = .working
            }
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.step)

        case .notification:
            let type = e.notificationType ?? ""
            let text = (e.message ?? "").lowercased()
            if type == "permission_prompt" || (type.isEmpty && text.contains("permission")) {
                // Claude pregunta en la terminal (p. ej. el hook no respondió).
                if !waiting {
                    info.status = .needsPermission
                    Self.addStep(&info, e.stepDescription, now)
                    signals.append(.needsPermission)
                }
            } else if type == "elicitation_dialog" || type == "agent_needs_input" {
                if !waiting {
                    info.status = .question
                    Self.addStep(&info, e.stepDescription, now)
                    signals.append(.question)
                }
            }
            // "idle_prompt" y el resto: solo actualizan la hora.

        case .stop:
            info.status = .finished
            info.pendingTool = nil
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.finished)

        case .stopFailure:
            info.status = .failed
            info.pendingTool = nil
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.failed)

        case .subagentStart:
            if !waiting { info.status = .working }
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.step)

        case .subagentStop:
            Self.addStep(&info, e.stepDescription, now)
            signals.append(.step)

        case .sessionEnd, .unknown:
            break
        }

        sessions[e.sessionID] = info
        return signals
    }

    /// El usuario respondió desde la isla.
    public mutating func resolvePermission(sessionID: String, allowed: Bool) {
        guard var info = sessions[sessionID] else { return }
        guard info.status == .needsPermission || info.status == .question else { return }
        info.status = allowed ? .working : .thinking
        info.pendingTool = nil
        Self.addStep(&info, allowed ? "Permiso concedido" : "Permiso denegado", Date())
        sessions[sessionID] = info
    }

    /// Paso del tiempo: "terminado" → "en reposo" a los 6 s; se olvidan las viejas.
    public mutating func tick(now: Date = Date()) {
        for (id, var info) in sessions {
            let age = now.timeIntervalSince(info.lastUpdate)
            switch info.status {
            case .finished where age >= Self.finishedLinger:
                info.status = .idle
                sessions[id] = info
            case .idle where age >= Self.idleExpiry:
                sessions[id] = nil
            default:
                if age >= Self.staleExpiry { sessions[id] = nil }
            }
        }
    }

    // MARK: - Ayudas

    private static func addStep(_ info: inout SessionInfo, _ text: String, _ now: Date) {
        info.steps.append(SessionStep(text: text, date: now))
        if info.steps.count > maxSteps {
            info.steps.removeFirst(info.steps.count - maxSteps)
        }
    }
}
