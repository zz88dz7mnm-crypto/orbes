import Foundation
import OrbexCore

/// Sonidos de ORBEX (informe §8.2). El `SoundEngine` los sintetiza según el tema activo.
enum OrbexSound: String, CaseIterable {
    case greet, peek, open, close, tap, annoyed, dizzy, rareBlink, sleep, wake
    case needsYou, permissionGranted, permissionDenied, answered, sessionDone, error
    case assistantMessage, thinking, fileSwallowed
    case timerStart, tick, timerDone, alarm, lap, noteSaved
    case newSong, toClock, toNotch, surprise
}

/// Reacciones puntuales del personaje.
enum OrbexReaction: String {
    case celebrate, worry, greet, love, surprised, thinking
}

/// Páginas del contenido de la isla abierta.
enum IslandPage: String, CaseIterable, Identifiable {
    case home, sessions, timers, notes, music, integrations
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .sessions: return "Código"
        case .timers: return "Timers"
        case .notes: return "Notas"
        case .music: return "Música"
        case .integrations: return "Servicios"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "circle.circle"
        case .sessions: return "terminal"
        case .timers: return "timer"
        case .notes: return "note.text"
        case .music: return "music.note"
        case .integrations: return "square.grid.2x2"
        }
    }
}

/// Bus de eventos entre módulos. Cada módulo (sesiones, timers, asistente, reloj, integraciones)
/// avisa por acá y la app (AppModel) decide sonidos, estado de la isla y reacciones.
/// Todas las funciones se pueden llamar desde cualquier hilo: publican en el hilo principal.
enum OrbexBus {
    static let sound = Notification.Name("orbex.bus.sound")
    static let reaction = Notification.Name("orbex.bus.reaction")
    static let activity = Notification.Name("orbex.bus.activity")
    static let showPage = Notification.Name("orbex.bus.showPage")
    static let command = Notification.Name("orbex.bus.command")
    static let tint = Notification.Name("orbex.bus.tint")
    static let toast = Notification.Name("orbex.bus.toast")

    /// Reproduce un sonido.
    static func play(_ s: OrbexSound) { post(sound, s.rawValue) }

    /// Hace reaccionar al personaje.
    static func react(_ r: OrbexReaction) { post(reaction, r.rawValue) }

    /// Marca que una fuente (p. ej. "timers", "claude:<id>") está trabajando o necesita al usuario.
    /// `working` = isla en "trabajando"; `attention` = isla en "te necesita".
    static func setActivity(source: String, working: Bool, attention: Bool) {
        post(activity, ActivityUpdate(source: source, working: working, attention: attention))
    }

    /// Abre la isla en una página.
    static func show(_ page: IslandPage) { post(showPage, page.rawValue) }

    /// Acciones globales: "assistant", "clock", "settings", "open", "close".
    static func perform(_ action: String) { post(command, action) }

    /// Color del personaje pedido por una integración (`nil` = volver al elegido por el usuario).
    static func requestTint(_ tint: OrbexTint?, source: String) {
        post(Self.tint, TintRequest(source: source, tint: tint))
    }

    /// Mensaje corto que la isla muestra unos segundos (p. ej. "Nota guardada").
    static func toast(_ text: String, symbol: String = "checkmark.circle") {
        post(Self.toast, Toast(text: text, symbol: symbol))
    }

    struct ActivityUpdate { let source: String; let working: Bool; let attention: Bool }
    struct TintRequest { let source: String; let tint: OrbexTint? }
    struct Toast: Equatable { let text: String; let symbol: String }

    private static func post(_ name: Notification.Name, _ object: Any) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: name, object: object)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: name, object: object) }
        }
    }
}
