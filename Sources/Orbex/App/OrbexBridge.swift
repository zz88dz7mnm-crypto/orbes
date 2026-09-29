import AppKit
import Combine
import SwiftUI
import OrbexCore

/// Puente entre ORBEX (bus, `AppModel`, módulos) y la isla (base Coucou: `AppState` + `IslandWindowController`).
///
/// Todo lo que un módulo pide —abrir la isla, mostrar un aviso, "estoy trabajando", festejar, pasar a
/// reloj— pasa por acá y se traduce a la isla. Y cada cambio de la isla (modo, vista) vuelve a
/// `AppModel` como espejo (`islandState`) para los módulos que lo miran.
@MainActor
final class OrbexBridge {
    static let shared = OrbexBridge()

    private(set) weak var island: IslandWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var noteReturn: DispatchWorkItem?

    private var state: AppState { AppState.shared }

    private init() {}

    // MARK: - Arranque

    func attach(_ controller: IslandWindowController) {
        island = controller

        Publishers.CombineLatest(state.$mode, state.$view)
            .receive(on: DispatchQueue.main)
            .sink { mode, view in
                MainActor.assumeIsolated { AppModel.shared.islandDidChange(mode: mode, view: view) }
            }
            .store(in: &cancellables)

        // "Cerrar después de N s": en la base el ajuste solo movía la barrita; ahora cierra de verdad.
        state.$autoCloseInterval
            .receive(on: DispatchQueue.main)
            .sink { secs in
                MainActor.assumeIsolated { OrbexBridge.shared.island?.fsm.homeToPetitDelay = max(5, secs) }
            }
            .store(in: &cancellables)

        let nc = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, Notification.Name.orbexPlacementNeedsUpdate] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { OrbexBridge.shared.updatePlacement() }
            })
        }
        updatePlacement()
    }

    /// Mide el notch (pantalla elegida + ajuste fino) y se lo pasa a `AppModel` para Configuración.
    func updatePlacement() {
        let s = AppModel.shared.settings
        guard let place = NotchDetector.placement(for: s.screen, adjustW: s.notchAdjustWidth,
                                                  adjustH: s.notchAdjustHeight) else { return }
        AppModel.shared.updatePlacement(notch: place.notch, screenSize: place.screen.frame.size)
    }

    // MARK: - Abrir, cerrar, asomar

    /// Abre la isla en una vista (o en la de siempre: resumen si hay pastillas, vacía si no).
    func openIsland(_ view: IslandView? = nil) {
        guard let island else { return }
        cancelNoteReturn()
        if ClockController.shared.isVisible { hideClock() }
        island.expand(to: view ?? island.defaultView())
    }

    func close() {
        cancelNoteReturn()
        island?.collapse()
    }

    /// Asoma la isla compacta (si estaba escondida) para mostrar dónde vive ORBEX o que algo pasó.
    func reveal() {
        guard state.mode == .hidden, !ClockController.shared.isVisible else { return }
        island?.fsm.reveal()
    }

    func toggleAssistant() {
        if state.mode == .expanded && state.view == .prompt { close() } else { openIsland(.prompt) }
    }

    /// Páginas de ORBEX → vistas de la isla.
    func show(page: IslandPage) {
        switch page {
        case .sessions:
            openIsland(SessionsStore.shared.approvals.isEmpty ? nil : .approval)
        case .home, .timers, .notes, .music, .integrations:
            openIsland()
        }
    }

    // MARK: - Reloj flotante

    func toggleClock() {
        if ClockController.shared.isVisible { hideClock() } else { showClock() }
    }

    private func showClock() {
        guard let island else { return }
        let rect = island.notchRectOnScreen()
        cancelNoteReturn()
        island.fsm.hide()
        ClockController.shared.show(from: rect)
        OrbexBus.play(.toClock)
        AppModel.shared.islandDidChange(mode: state.mode, view: state.view)
    }

    private func hideClock() {
        let rect = island?.notchRectOnScreen() ?? .zero
        ClockController.shared.hide(to: rect)
        OrbexBus.play(.toNotch)
        AppModel.shared.islandDidChange(mode: state.mode, view: state.view)
    }

    // MARK: - Avisos

    /// Aviso corto ("Nota guardada", "¡Terminó el timer!"): la isla muestra la vista `note` unos segundos
    /// y vuelve a donde estaba. Nunca tapa algo que espera al usuario (permiso, pregunta, mail, chat).
    func showNote(_ text: String, symbol: String) {
        guard island != nil else { return }
        let busy: Set<IslandView> = [.approval, .question, .mail, .prompt, .upload, .uploading, .choose, .greeting]
        if state.mode == .expanded && busy.contains(state.view) { return }
        let wasExpanded = state.mode == .expanded
        let previous = state.view
        state.noteMessage = text
        state.noteSymbol = symbol
        openIsland(.note)
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let bridge = OrbexBridge.shared
                let s = AppState.shared
                guard s.mode == .expanded, s.view == .note else { return }
                if wasExpanded && previous != .note { s.view = previous } else { bridge.close() }
            }
        }
        noteReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    private func cancelNoteReturn() {
        noteReturn?.cancel()
        noteReturn = nil
    }

    // MARK: - Actividad y reacciones → personaje de la isla

    /// Estado de fondo del personaje según lo que hacen los módulos (timers, asistente, recordatorios).
    func setAmbient(working: Bool, attention: Bool, sleepy: Bool) {
        let s: BotState? = attention ? .approval : (working ? .working : (sleepy ? .sleeping : nil))
        if state.ambientState != s { state.ambientState = s }
    }

    func react(_ r: OrbexReaction) {
        let nc = NotificationCenter.default
        switch r {
        case .celebrate: nc.post(name: .triggerEmote, object: BotEmote.proud)
        case .worry: nc.post(name: .triggerEmote, object: BotEmote.surprised)
        case .greet: nc.post(name: .botGreet, object: nil)
        case .love: nc.post(name: .triggerEmote, object: BotEmote.love)
        case .surprised: nc.post(name: .triggerEmote, object: BotEmote.surprised)
        case .thinking: nc.post(name: .triggerEmote, object: BotEmote.happy)
        }
    }
}
