import AppKit
import SwiftUI
import OrbexCore

/// Permiso pendiente que Claude Code (o Codex) está esperando.
struct PendingApproval: Identifiable {
    let id: UUID
    let event: HookEvent
    let respond: (Bool?, String?) -> Void
    /// Cuándo llegó (el `HookServer` responde "sin decisión" solo a los 105 s).
    var received: Date = Date()
}

/// Lo que decide el usuario ante un permiso.
enum ApprovalDecision {
    /// Permitir esta vez.
    case allow
    /// Permitir y recordar (proyecto + herramienta). La vista pide una segunda confirmación antes.
    case allowAlways
    /// Denegar.
    case deny
}

/// Claves de ajustes de las sesiones.
enum SessionsKeys {
    static let alwaysAllow = "orbex.sessions.alwaysAllow"
    static let autoOpen = "orbex.sessions.autoOpen"
    static let showCodex = "orbex.sessions.showCodex"
    static let terminal = "orbex.sessions.terminal"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }
}

/// Sesiones en vivo de Claude Code / Codex y los permisos que esperan respuesta.
/// Recibe los eventos del `HookServer` (siempre en el hilo principal).
@MainActor
final class SessionsStore: ObservableObject {
    static let shared = SessionsStore()

    @Published private(set) var sessions: [SessionInfo] = []
    @Published private(set) var approvals: [PendingApproval] = []

    private var tracker = SessionTracker()
    private var started = false
    private var tickTimer: Timer?
    /// Fuentes que ya avisamos al bus (para limpiarlas cuando la sesión se va).
    private var activeSources: [String: (working: Bool, attention: Bool)] = [:]
    /// Última línea que pusimos en `AppModel.statusLine` (para no pisar la de otros módulos).
    private var lastPublishedLine = ""

    private init() {}

    // MARK: - Arranque

    func start() {
        guard !started else { return }
        started = true
        let server = HookServer.shared
        server.onEvent = { event in
            if Thread.isMainThread {
                MainActor.assumeIsolated { SessionsStore.shared.receive(event) }
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { SessionsStore.shared.receive(event) }
                }
            }
        }
        server.onPermissionRequest = { event, respond in
            if Thread.isMainThread {
                MainActor.assumeIsolated { SessionsStore.shared.receivePermission(event, respond: respond) }
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { SessionsStore.shared.receivePermission(event, respond: respond) }
                }
            }
        }
        server.start()

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { SessionsStore.shared.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: - Eventos

    private var showCodex: Bool { SessionsKeys.bool(SessionsKeys.showCodex, default: true) }

    private func isHidden(_ event: HookEvent) -> Bool {
        event.source == .codex && !showCodex
    }

    private func receive(_ event: HookEvent) {
        guard !isHidden(event) else { return }
        let signals = tracker.apply(event, now: Date())
        dropStaleApprovals(for: event)
        handle(signals, event: event)
        publish()
    }

    private func receivePermission(_ event: HookEvent, respond: @escaping (Bool?, String?) -> Void) {
        // Codex oculto: que la herramienta pregunte como siempre.
        guard !isHidden(event) else { respond(nil, nil); return }

        // Regla "Siempre permitir" (proyecto + herramienta) → se permite sin preguntar.
        if isAlwaysAllowed(event) {
            respond(true, "Permitido siempre desde ORBEX")
            _ = tracker.apply(event, now: Date())
            tracker.resolvePermission(sessionID: event.sessionID, allowed: true)
            publish()
            return
        }

        let signals = tracker.apply(event, now: Date())
        let approval = PendingApproval(id: UUID(), event: event, respond: respond)
        approvals.append(approval)
        let alreadyNotified = signals.contains { $0 == .needsPermission || $0 == .question }
        handle(signals, event: event)
        if !alreadyNotified { playNeedsYou() }
        if SessionsKeys.bool(SessionsKeys.autoOpen, default: true) {
            OrbexBus.show(.sessions)
        }
        publish()
    }

    /// Si la sesión siguió adelante (se respondió en la terminal o venció), el permiso ya no espera nada.
    private func dropStaleApprovals(for event: HookEvent) {
        guard approvals.contains(where: { $0.event.sessionID == event.sessionID }) else { return }
        guard let info = tracker.sorted.first(where: { "\($0.id)" == "\(event.sessionID)" }) else {
            removeApprovals(ofSession: "\(event.sessionID)")
            return
        }
        if info.status != .needsPermission && info.status != .question {
            removeApprovals(ofSession: "\(event.sessionID)")
        }
    }

    private func removeApprovals(ofSession sessionID: String) {
        let stale = approvals.filter { "\($0.event.sessionID)" == sessionID }
        guard !stale.isEmpty else { return }
        approvals.removeAll { "\($0.event.sessionID)" == sessionID }
        // Sin decisión: la herramienta sigue con su flujo normal.
        for a in stale { a.respond(nil, nil) }
    }

    private func handle(_ signals: [SessionSignal], event: HookEvent) {
        for signal in signals {
            switch signal {
            case .started:
                break
            case .step:
                break
            case .needsPermission, .question:
                playNeedsYou()
            case .finished:
                OrbexBus.play(.sessionDone)
                OrbexBus.react(.celebrate)
            case .failed:
                OrbexBus.play(.error)
                OrbexBus.react(.worry)
            @unknown default:
                break
            }
        }
    }

    /// El `AppModel` ya suena "te necesita" cuando la isla pasa a ese estado;
    /// solo sonamos acá si la isla no va a cambiar (ya pedía atención o está abierta).
    private func playNeedsYou() {
        let model = AppModel.shared
        if !model.attentionSources.isEmpty || model.islandState.isExpanded {
            OrbexBus.play(.needsYou)
        }
    }

    // MARK: - Decisiones

    func decide(_ id: UUID, _ d: ApprovalDecision) {
        guard let index = approvals.firstIndex(where: { $0.id == id }) else { return }
        let approval = approvals.remove(at: index)
        let event = approval.event
        switch d {
        case .allow:
            approval.respond(true, nil)
            tracker.resolvePermission(sessionID: event.sessionID, allowed: true)
            OrbexBus.play(.permissionGranted)
        case .allowAlways:
            remember(event)
            approval.respond(true, "Permitido siempre desde ORBEX")
            tracker.resolvePermission(sessionID: event.sessionID, allowed: true)
            OrbexBus.play(.permissionGranted)
        case .deny:
            approval.respond(false, "Denegado desde ORBEX")
            tracker.resolvePermission(sessionID: event.sessionID, allowed: false)
            OrbexBus.play(.permissionDenied)
        }
        publish()
    }

    /// Sin decisión: la herramienta sigue con su flujo normal (Claude pregunta en la terminal)
    /// y saltamos a esa terminal. Se usa para las preguntas (`AskUserQuestion`).
    func passToTerminal(_ id: UUID) {
        guard let index = approvals.firstIndex(where: { $0.id == id }) else { return }
        let approval = approvals.remove(at: index)
        approval.respond(nil, nil)
        if let s = tracker.sessions[approval.event.sessionID] {
            TerminalJumper.jump(to: s)
        }
        publish()
    }

    // MARK: - "Siempre permitir"

    private static func ruleKey(_ event: HookEvent) -> String? {
        // Las preguntas no se "permiten siempre": las responde el usuario cada vez.
        guard !event.isQuestion, let tool = event.toolName, !tool.isEmpty else { return nil }
        return "\(event.source == .codex ? "codex" : "claude")|\(event.projectName)|\(tool)"
    }

    private func isAlwaysAllowed(_ event: HookEvent) -> Bool {
        guard let key = Self.ruleKey(event) else { return false }
        return alwaysAllowRules.contains(key)
    }

    private func remember(_ event: HookEvent) {
        guard let key = Self.ruleKey(event) else { return }
        var rules = alwaysAllowRules
        if !rules.contains(key) { rules.append(key) }
        UserDefaults.standard.set(rules, forKey: SessionsKeys.alwaysAllow)
    }

    /// Reglas guardadas: "claude|proyecto|herramienta".
    var alwaysAllowRules: [String] {
        UserDefaults.standard.stringArray(forKey: SessionsKeys.alwaysAllow) ?? []
    }

    func forgetAlwaysAllowRules() {
        UserDefaults.standard.removeObject(forKey: SessionsKeys.alwaysAllow)
        objectWillChange.send()
    }

    // MARK: - Reloj

    private func tick() {
        tracker.tick(now: Date())
        // Permisos de sesiones que ya no existen: no esperan nada.
        let ids = Set(tracker.sorted.map(\.id))
        // Y los que ya vencieron: el servidor respondió "sin decisión" y Claude pregunta en la terminal.
        let now = Date()
        let orphaned = approvals.filter {
            !ids.contains($0.event.sessionID)
                || now.timeIntervalSince($0.received) > HookServer.permissionTimeout + 1
        }
        if !orphaned.isEmpty {
            approvals.removeAll { a in orphaned.contains { $0.id == a.id } }
            for a in orphaned { a.respond(nil, nil) }
        }
        publish()
    }

    // MARK: - Publicar

    private func publish() {
        var list = tracker.sorted
        if !showCodex { list = list.filter { $0.source != .codex } }

        if list != sessions { sessions = list }
        updateActivity(list)
        updateStatusLine()
    }

    private func updateActivity(_ list: [SessionInfo]) {
        var next: [String: (working: Bool, attention: Bool)] = [:]
        for s in list {
            let hasApproval = approvals.contains { "\($0.event.sessionID)" == "\(s.id)" }
            let working = s.status == .working || s.status == .thinking
            let attention = hasApproval || s.status == .needsPermission || s.status == .question
            if working || attention {
                next["claude:\(s.id)"] = (working, attention)
            }
        }
        // Avisar solo lo que cambió.
        for (source, value) in next {
            if let old = activeSources[source], old.working == value.working, old.attention == value.attention { continue }
            OrbexBus.setActivity(source: source, working: value.working, attention: value.attention)
        }
        for source in activeSources.keys where next[source] == nil {
            OrbexBus.setActivity(source: source, working: false, attention: false)
        }
        activeSources = next
    }

    private func updateStatusLine() {
        let line = statusLine
        let model = AppModel.shared
        if !line.isEmpty {
            // La línea de los timers tiene prioridad (el agente principal arbitra después).
            if TimersStore.shared.statusLine.isEmpty, model.statusLine != line {
                model.statusLine = line
            }
            lastPublishedLine = line
        } else if !lastPublishedLine.isEmpty {
            if model.statusLine == lastPublishedLine {
                model.statusLine = TimersStore.shared.statusLine
            }
            lastPublishedLine = ""
        }
    }

    // MARK: - Derivados

    /// Sesión más relevante: la que pide algo; si no, la última que está trabajando.
    var focusSession: SessionInfo? {
        if let first = approvals.first,
           let s = sessions.first(where: { "\($0.id)" == "\(first.event.sessionID)" }) {
            return s
        }
        if let s = sessions.first(where: { $0.status == .needsPermission || $0.status == .question }) {
            return s
        }
        return sessions
            .filter { $0.status == .working || $0.status == .thinking }
            .max(by: { $0.lastUpdate < $1.lastUpdate })
    }

    /// "Claude · orbes: Edita main.swift". Vacío si no hay nada en marcha.
    var statusLine: String {
        guard let s = focusSession else { return "" }
        return "\(Self.sourceName(s)) · \(s.project): \(Self.detail(for: s))"
    }

    /// Cantidad de sesiones visibles que no terminaron.
    var activeCount: Int {
        sessions.filter { $0.status != .finished && $0.status != .failed }.count
    }

    var needsAttention: Bool {
        !approvals.isEmpty || sessions.contains { $0.status == .needsPermission || $0.status == .question }
    }

    var isWorking: Bool {
        sessions.contains { $0.status == .working || $0.status == .thinking }
    }

    func approvals(for s: SessionInfo) -> [PendingApproval] {
        approvals.filter { "\($0.event.sessionID)" == "\(s.id)" }
    }

    // MARK: - Textos

    static func sourceName(_ s: SessionInfo) -> String {
        s.source == .codex ? "Codex" : "Claude"
    }

    static func sourceName(_ e: HookEvent) -> String {
        e.source == .codex ? "Codex" : "Claude"
    }

    /// Último paso o, si no hay, el estado en palabras.
    static func detail(for s: SessionInfo) -> String {
        switch s.status {
        case .needsPermission:
            return "Necesita tu permiso"
        case .question:
            return "Te está preguntando algo"
        case .finished:
            return s.steps.last.map { "Listo · \($0.text)" } ?? "Listo"
        case .failed:
            return "Falló"
        default:
            if let step = s.steps.last, !step.text.isEmpty { return step.text }
            return statusText(s.status)
        }
    }

    static func statusText(_ status: SessionStatus) -> String {
        switch status {
        case .idle: return "En espera"
        case .thinking: return "Pensando…"
        case .working: return "Trabajando…"
        case .needsPermission: return "Necesita tu permiso"
        case .question: return "Te está preguntando algo"
        case .finished: return "Listo"
        case .failed: return "Falló"
        @unknown default: return ""
        }
    }
}
