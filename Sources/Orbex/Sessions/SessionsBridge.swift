import AppKit
import Combine
import OrbexCore

/// Puente sesiones de Claude Code / Codex (`SessionsStore`, motor de ORBEX) ↔ isla (base: `AppState`).
///
/// - Una pastilla `AgentTask` por sesión activa (id `claude:<sessionID>`, nombre = proyecto, color
///   estable, estado del personaje según la sesión, pasos en castellano del tracker). Al terminar
///   queda unos segundos y se va.
/// - Cola de permisos: el primero se muestra fijo (vista `approval`, o `question` si es
///   `AskUserQuestion`) hasta que el usuario decide. Nunca se aprueba nada sin un clic.
/// - Terminado / error: vistas `finished` / `error` con los datos reales de la sesión.
@MainActor
final class SessionsBridge: ObservableObject {
    static let shared = SessionsBridge()

    /// Prefijo de las pastillas de sesión.
    static let taskPrefix = "claude:"

    /// Última sesión que terminó o falló (para `FinishedView` / `ErrorView`, aunque la pastilla ya se haya ido).
    @Published private(set) var endedSession: SessionInfo?

    /// Cuánto queda la pastilla después de terminar / fallar.
    /// (Igual que el tracker: a los 6 s "terminado" pasa a "en reposo" y la pastilla se va.)
    static let finishedLinger: TimeInterval = SessionTracker.finishedLinger
    static let failedLinger: TimeInterval = 30

    private var cancellables: Set<AnyCancellable> = []
    private var started = false
    private var shownApprovalID: UUID?
    /// Estado anterior de cada sesión (para detectar transiciones).
    private var lastStatus: [String: SessionStatus] = [:]
    /// Cuándo terminó / falló cada sesión (para sacar la pastilla).
    private var endedAt: [String: Date] = [:]
    /// Pasos acumulados por sesión (el tracker guarda solo los últimos 20; el ticker anima por cantidad).
    private var stepLog: [String: (ids: Set<UUID>, texts: [String])] = [:]
    /// Pregunta sin permiso asociado que abrimos (se cierra cuando la sesión sigue).
    private var shownQuestionSession: String?
    private var cleanupWork: DispatchWorkItem?

    private init() {}

    private var autoOpen: Bool { SessionsKeys.bool(SessionsKeys.autoOpen, default: true) }

    // MARK: - Arranque

    func start() {
        guard !started else { return }
        started = true
        let store = SessionsStore.shared
        Publishers.CombineLatest(store.$sessions, store.$approvals)
            .receive(on: DispatchQueue.main)
            .sink { sessions, approvals in
                MainActor.assumeIsolated { SessionsBridge.shared.sync(sessions, approvals) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Sincronizar

    private func sync(_ sessions: [SessionInfo], _ approvals: [PendingApproval]) {
        let now = Date()
        var transitions: [(SessionInfo, SessionStatus?)] = []
        var seen = Set<String>()
        for s in sessions {
            seen.insert(s.id)
            let old = lastStatus[s.id]
            if old != s.status { transitions.append((s, old)) }
            lastStatus[s.id] = s.status
            if s.status == .finished || s.status == .failed {
                if endedAt[s.id] == nil || old != s.status { endedAt[s.id] = now }
            } else if s.status != .idle {
                endedAt[s.id] = nil
            }
        }
        for id in lastStatus.keys where !seen.contains(id) {
            lastStatus[id] = nil
            endedAt[id] = nil
            stepLog[id] = nil
        }

        updatePills(sessions, approvals, now: now)
        updateApproval(approvals)
        for (s, old) in transitions { handleTransition(s, from: old, approvals: approvals) }
        scheduleCleanup(now: now)
    }

    /// ¿La sesión tiene pastilla?
    private func isVisible(_ s: SessionInfo, hasApproval: Bool, now: Date) -> Bool {
        if hasApproval { return true }
        switch s.status {
        case .idle:
            return false
        case .finished:
            return now.timeIntervalSince(endedAt[s.id] ?? now) < Self.finishedLinger
        case .failed:
            return now.timeIntervalSince(endedAt[s.id] ?? now) < Self.failedLinger
        default:
            return true
        }
    }

    private func updatePills(_ sessions: [SessionInfo], _ approvals: [PendingApproval], now: Date) {
        let state = AppState.shared
        var wanted = Set<String>()
        var tasks = state.tasks

        for s in sessions.reversed() {  // `sorted` pone primero lo urgente: insertamos al revés.
            let pending = approvals.filter { $0.event.sessionID == s.id }
            guard isVisible(s, hasApproval: !pending.isEmpty, now: now) else { continue }
            let id = Self.taskID(s.id)
            wanted.insert(id)
            let bot = Self.botState(s, pending: pending)
            let steps = accumulatedSteps(s)
            let focused = state.focusId == id
            if let i = tasks.firstIndex(where: { $0.id == id }) {
                var t = tasks[i]
                t.name = Self.pillName(s)
                t.state = bot
                if t.steps != steps {
                    t.steps = steps
                    t.stepIndex = max(0, steps.count - 1)
                }
                t.sessionCwd = s.cwd
                t.pillBadge = focused ? nil : Self.badge(for: bot)
                if t != tasks[i] { tasks[i] = t }
            } else {
                var t = AgentTask(id: id, name: Self.pillName(s), color: Self.color(for: s.id), state: bot,
                                  stepIndex: max(0, steps.count - 1), steps: steps, source: .claudeCode)
                t.sessionCwd = s.cwd
                t.pillBadge = focused ? nil : Self.badge(for: bot)
                // Adelante de las integraciones: así se ve entre las pastillas de la isla.
                tasks.insert(t, at: 0)
            }
        }
        tasks.removeAll { $0.id.hasPrefix(Self.taskPrefix) && !wanted.contains($0.id) }

        if tasks != state.tasks {
            state.tasks = tasks
            if let f = state.focusId, !tasks.contains(where: { $0.id == f }) {
                state.focusId = tasks.contains(where: { $0.id == "integration_claude" })
                    ? "integration_claude" : tasks.first?.id
            }
            state.syncMode()
            state.syncView()
        }
    }

    /// Pasos acumulados (tope 200; al llegar se reinicia con los últimos 10 para que el ticker siga animando).
    private func accumulatedSteps(_ s: SessionInfo) -> [String] {
        var log = stepLog[s.id] ?? (ids: [], texts: [])
        for step in s.steps where !log.ids.contains(step.id) {
            log.ids.insert(step.id)
            log.texts.append(step.text)
        }
        if log.texts.count > 200 {
            log.texts = Array(log.texts.suffix(10))
            log.ids = Set(s.steps.map(\.id))
        }
        stepLog[s.id] = log
        return log.texts
    }

    // MARK: - Permisos y preguntas

    private func updateApproval(_ list: [PendingApproval]) {
        let state = AppState.shared
        guard let first = list.first else {
            guard shownApprovalID != nil else { return }
            shownApprovalID = nil
            state.pendingApproval = nil
            guard state.mode == .expanded && (state.view == .approval || state.view == .question) else { return }
            if questionSession != nil {
                // Queda una pregunta que se contesta en la terminal.
                if state.view != .question { OrbexBridge.shared.openIsland(.question) }
                state.isPinned = true
            } else {
                state.isPinned = false
                OrbexBridge.shared.close()
            }
            return
        }
        guard first.id != shownApprovalID else { return }
        shownApprovalID = first.id
        let e = first.event
        state.pendingApproval = ApprovalInfo(sessionId: e.sessionID,
                                             tool: e.toolName ?? "Herramienta",
                                             command: e.toolInputSummary ?? e.message ?? e.stepDescription)
        let id = Self.taskID(e.sessionID)
        if state.tasks.contains(where: { $0.id == id }) { state.setFocus(id) }

        let view: IslandView = e.isQuestion ? .question : .approval
        let alreadyShowing = state.mode == .expanded && (state.view == .approval || state.view == .question)
        if autoOpen || alreadyShowing {
            OrbexBridge.shared.openIsland(view)
            state.isPinned = true
        } else {
            OrbexBridge.shared.reveal()
        }
    }

    private func handleTransition(_ s: SessionInfo, from old: SessionStatus?, approvals: [PendingApproval]) {
        let state = AppState.shared
        let id = Self.taskID(s.id)
        let hasApproval = approvals.contains { $0.event.sessionID == s.id }

        // Pregunta sin permiso asociado (llegó por PreToolUse o Notification): la mostramos igual.
        if s.status == .question && !hasApproval {
            if state.tasks.contains(where: { $0.id == id }) { state.setFocus(id) }
            shownQuestionSession = s.id
            if autoOpen && approvals.isEmpty {
                OrbexBridge.shared.openIsland(.question)
                state.isPinned = true
            } else {
                OrbexBridge.shared.reveal()
            }
            return
        }
        if old == .question && shownQuestionSession == s.id {
            shownQuestionSession = nil
            if approvals.isEmpty && state.mode == .expanded && state.view == .question {
                state.isPinned = false
                OrbexBridge.shared.close()
            }
        }

        guard s.status == .finished || s.status == .failed else {
            if (old == nil || old == .idle) && s.status != .idle {
                // Sesión nueva en marcha: se enfoca si la isla no miraba otra cosa en particular.
                if state.focusId == nil || state.focusId == "integration_claude",
                   state.tasks.contains(where: { $0.id == id }) {
                    state.setFocus(id)
                }
                OrbexBridge.shared.reveal()
            }
            return
        }
        guard old != nil, old != .idle else { return }  // no avisar de sesiones viejas al arrancar
        endedSession = s

        // No tapar lo que espera al usuario (permiso, pregunta, chat, mail…).
        let busy: Set<IslandView> = [.approval, .question, .mail, .prompt, .upload, .uploading, .choose,
                                     .greeting, .settings, .searching, .result]
        if state.mode == .expanded && busy.contains(state.view) { return }
        if state.tasks.contains(where: { $0.id == id }) { state.setFocus(id) }
        if autoOpen {
            // Sin fijar: la isla se cierra sola como siempre (FSM + "cerrar después de N s").
            OrbexBridge.shared.openIsland(s.status == .failed ? .error : .finished)
        } else {
            OrbexBridge.shared.reveal()
        }
    }

    /// Vuelve a sincronizar cuando vence la estadía de una pastilla terminada.
    private func scheduleCleanup(now: Date) {
        cleanupWork?.cancel()
        let store = SessionsStore.shared
        var next: TimeInterval?
        for s in store.sessions {
            guard let at = endedAt[s.id] else { continue }
            let linger = s.status == .failed ? Self.failedLinger : Self.finishedLinger
            let left = linger - now.timeIntervalSince(at)
            if left > 0 { next = min(next ?? left, left) }
        }
        guard let delay = next else { return }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let st = SessionsStore.shared
                SessionsBridge.shared.sync(st.sessions, st.approvals)
            }
        }
        cleanupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1, execute: work)
    }

    // MARK: - Acciones de las vistas

    /// Permiso que se muestra ahora (el primero de la cola).
    var currentApproval: PendingApproval? { SessionsStore.shared.approvals.first }

    /// Botones de la vista de permiso. "Siempre" ya viene doblemente confirmado por la vista.
    func decide(_ decision: ApprovalDecision) {
        guard let first = currentApproval else {
            AppState.shared.pendingApproval = nil
            return
        }
        SessionsStore.shared.decide(first.id, decision)
    }

    /// Compatibilidad con la vista vieja: "allow", "deny", "always".
    func sendApprovalDecision(_ raw: String) {
        switch raw {
        case "allow": decide(.allow)
        case "always": decide(.allowAlways)
        default: decide(.deny)
        }
    }

    /// La pregunta se contesta en la terminal: ORBEX no elige nada. Sin decisión + saltar a la terminal.
    func answerInTerminal() {
        if let first = currentApproval, first.event.isQuestion {
            // Sin decisión: Claude pregunta en su terminal y saltamos ahí.
            SessionsStore.shared.passToTerminal(first.id)
        } else if let s = questionSession ?? session(forTask: AppState.shared.focusTask?.id) {
            TerminalJumper.jump(to: s)
        }
        if SessionsStore.shared.approvals.isEmpty {
            shownQuestionSession = nil
            AppState.shared.isPinned = false
            OrbexBridge.shared.close()
        }
    }

    /// Salta a la terminal de la sesión (del permiso actual o de la pastilla enfocada).
    func jumpToTerminal(sessionID: String? = nil) {
        let store = SessionsStore.shared
        let id = sessionID ?? currentApproval?.event.sessionID
            ?? AppState.shared.focusTask.flatMap { Self.sessionID(fromTask: $0.id) }
            ?? endedSession?.id
        guard let id else { return }
        if let s = store.sessions.first(where: { $0.id == id }) {
            TerminalJumper.jump(to: s)
        } else if let s = endedSession, s.id == id {
            TerminalJumper.jump(to: s)
        }
    }

    /// Abre la página de sesiones: el permiso o la pregunta pendiente, si hay; si no, el resumen.
    func openSessionsPage() {
        let state = AppState.shared
        if let first = currentApproval {
            OrbexBridge.shared.openIsland(first.event.isQuestion ? .question : .approval)
            state.isPinned = true
        } else if questionSession != nil {
            OrbexBridge.shared.openIsland(.question)
            state.isPinned = true
        } else {
            if let s = SessionsStore.shared.focusSession {
                let id = Self.taskID(s.id)
                if state.tasks.contains(where: { $0.id == id }) { state.setFocus(id) }
            }
            OrbexBridge.shared.openIsland()
        }
    }

    // MARK: - Datos para las vistas

    /// Sesión que pregunta algo sin permiso pendiente (pregunta llegada por PreToolUse / Notification).
    var questionSession: SessionInfo? {
        let sessions = SessionsStore.shared.sessions
        if let id = shownQuestionSession, let s = sessions.first(where: { $0.id == id }), s.status == .question {
            return s
        }
        return sessions.first { $0.status == .question }
    }

    func session(forTask taskID: String?) -> SessionInfo? {
        guard let id = taskID.flatMap(Self.sessionID(fromTask:)) else { return nil }
        if let s = SessionsStore.shared.sessions.first(where: { $0.id == id }) { return s }
        if let s = endedSession, s.id == id { return s }
        return nil
    }

    /// Sesión para las vistas de terminado / error: la enfocada si terminó; si no, la última que terminó.
    func endedSession(for status: SessionStatus) -> SessionInfo? {
        if let s = session(forTask: AppState.shared.focusTask?.id), s.status == status { return s }
        if let s = endedSession, s.status == status { return s }
        return nil
    }

    /// Pastilla (para `AgentWho`) de una sesión, exista o no todavía en `AppState`.
    func task(forSession id: String) -> AgentTask? {
        let tid = Self.taskID(id)
        if let t = AppState.shared.tasks.first(where: { $0.id == tid }) { return t }
        guard let s = SessionsStore.shared.sessions.first(where: { $0.id == id })
                ?? (endedSession?.id == id ? endedSession : nil) else { return nil }
        return AgentTask(id: tid, name: Self.pillName(s), color: Self.color(for: s.id), state: .idle,
                         steps: [], source: .claudeCode)
    }

    // MARK: - Ayudas

    static func taskID(_ sessionID: String) -> String { taskPrefix + sessionID }

    static func sessionID(fromTask id: String) -> String? {
        guard id.hasPrefix(taskPrefix) else { return nil }
        return String(id.dropFirst(taskPrefix.count))
    }

    static func pillName(_ s: SessionInfo) -> String {
        s.source == .codex ? "\(s.project) · Codex" : s.project
    }

    static func botState(_ s: SessionInfo, pending: [PendingApproval]) -> BotState {
        if let p = pending.first { return p.event.isQuestion ? .question : .approval }
        switch s.status {
        case .idle: return .idle
        case .thinking: return .thinking
        case .working: return .working
        case .needsPermission: return .approval
        case .question: return .question
        case .finished: return .finished
        case .failed: return .error
        }
    }

    static func badge(for state: BotState) -> PillBadge? {
        switch state {
        case .approval, .question: return .approval
        case .finished: return .finished
        case .error: return .error
        default: return nil
        }
    }

    /// Paleta de las pastillas de sesión (distinta de las integraciones).
    private static let palette = ["#7DD3FC", "#A78BFA", "#F9A8D4", "#FCD34D", "#86EFAC",
                                  "#FDBA74", "#5EEAD4", "#C4B5FD", "#FDA4AF", "#93C5FD"]

    /// Color estable por sesión (hash FNV-1a, igual en cada arranque).
    static func color(for sessionID: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in sessionID.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return palette[Int(h % UInt64(palette.count))]
    }

    /// "2 min 10 s": cuánto tardó el último pedido (desde que se mandó hasta el último evento).
    static func durationText(_ s: SessionInfo) -> String? {
        guard let start = s.steps.last(where: { $0.text.hasPrefix("Pedido") || $0.text == "Nuevo pedido" })?.date
        else { return nil }
        let secs = max(0, Int(s.lastUpdate.timeIntervalSince(start)))
        if secs < 60 { return "\(secs) s" }
        let m = secs / 60, r = secs % 60
        if m < 60 { return r == 0 ? "\(m) min" : "\(m) min \(r) s" }
        return "\(m / 60) h \(m % 60) min"
    }

    /// Último pedido del usuario (sin el prefijo "Pedido: ").
    static func lastPrompt(_ s: SessionInfo) -> String? {
        guard let step = s.steps.last(where: { $0.text.hasPrefix("Pedido: ") }) else { return nil }
        return String(step.text.dropFirst("Pedido: ".count))
    }

    /// Último paso con contenido antes del cierre ("Listo" / "Error: …").
    static func lastWork(_ s: SessionInfo) -> String? {
        let skip: Set<String> = ["Listo", "Permiso concedido", "Permiso denegado", "Sesión iniciada"]
        return s.steps.dropLast().last { step in
            !skip.contains(step.text) && !step.text.hasPrefix("Pedido") && step.text != "Nuevo pedido"
        }?.text
    }
}
