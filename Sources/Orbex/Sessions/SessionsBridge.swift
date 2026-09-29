import AppKit
import Combine
import OrbexCore

/// Puente sesiones de Claude Code (`SessionsStore`, motor de ORBEX) ↔ isla (vistas de la base).
/// Versión mínima: el primer permiso pendiente se muestra en la vista `approval` (fija hasta decidir)
/// y sus botones llaman a `SessionsStore.decide`. Nunca se aprueba nada sin un clic del usuario.
@MainActor
final class SessionsBridge {
    static let shared = SessionsBridge()

    private var cancellables: Set<AnyCancellable> = []
    private var shownApprovalID: UUID?

    private init() {}

    func start() {
        SessionsStore.shared.$approvals
            .receive(on: DispatchQueue.main)
            .sink { list in
                MainActor.assumeIsolated { SessionsBridge.shared.approvalsChanged(list) }
            }
            .store(in: &cancellables)
    }

    private func approvalsChanged(_ list: [PendingApproval]) {
        let state = AppState.shared
        guard let first = list.first else {
            shownApprovalID = nil
            state.pendingApproval = nil
            if state.mode == .expanded && state.view == .approval {
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
        OrbexBridge.shared.openIsland(.approval)
        state.isPinned = true
    }

    /// Botones de la vista de permiso: "allow", "deny", "always".
    func sendApprovalDecision(_ raw: String) {
        let store = SessionsStore.shared
        guard let first = store.approvals.first else {
            AppState.shared.pendingApproval = nil
            return
        }
        let decision: ApprovalDecision
        switch raw {
        case "allow": decision = .allow
        case "always": decision = .allowAlways
        default: decision = .deny
        }
        store.decide(first.id, decision)
    }
}
