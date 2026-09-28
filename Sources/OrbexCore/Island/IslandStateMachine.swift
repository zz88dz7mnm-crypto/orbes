import Foundation

/// Estados visibles de la isla (informe §4.4 y §12).
public enum IslandState: String, Codable, CaseIterable, Sendable {
    /// Isla negra fundida con el notch.
    case hidden
    /// Asoma el techo de la esfera y los ojos (al pasar el mouse).
    case peek
    /// Trabajando: hay una sesión o tarea corriendo.
    case active
    /// Te necesita: permiso, pregunta o alarma.
    case needsYou
    /// Dormido: de noche o tras inactividad.
    case sleeping
    /// Abierto (home): personaje completo + contenido.
    case open
    /// Panel del asistente (más ancho).
    case assistant
    /// ORBEX se despegó del notch y es un reloj flotante.
    case clock

    /// Estados "de reposo": los que se muestran cuando nadie interactúa.
    public var isResting: Bool {
        switch self {
        case .hidden, .active, .needsYou, .sleeping: return true
        case .peek, .open, .assistant, .clock: return false
        }
    }

    /// Estados donde la isla está desplegada con contenido interactivo.
    public var isExpanded: Bool { self == .open || self == .assistant }
}

/// Lo que pasa "alrededor" de la isla y define su estado de reposo.
public struct IslandContext: Equatable, Sendable {
    public var isWorking: Bool
    public var needsAttention: Bool
    public var isSleepy: Bool

    public init(isWorking: Bool = false, needsAttention: Bool = false, isSleepy: Bool = false) {
        self.isWorking = isWorking
        self.needsAttention = needsAttention
        self.isSleepy = isSleepy
    }

    /// Prioridad: te necesita > trabajando > dormido > oculto.
    public var restingState: IslandState {
        if needsAttention { return .needsYou }
        if isWorking { return .active }
        if isSleepy { return .sleeping }
        return .hidden
    }
}

public enum IslandEvent: Equatable, Sendable {
    case mouseEntered
    case mouseExited
    /// Clic sobre la isla.
    case click
    /// Clic fuera de la isla (con la isla desplegada).
    case clickOutside
    case escape
    /// Abrir directamente (menú, atajo).
    case open
    /// Volver al reposo.
    case close
    case toggleAssistant
    case toggleClock
    case contextChanged(IslandContext)
}

/// Máquina de estados pura de la isla. No usa timers: la app llama a `tick(now:)`
/// periódicamente y la máquina resuelve los vencimientos. Así se prueba sin esperar.
public final class IslandStateMachine {

    public struct Config: Equatable, Sendable {
        /// Tiempo que queda asomado después de sacar el mouse.
        public var peekLinger: TimeInterval
        /// Tiempo que queda abierto sin el mouse encima antes de volver al reposo.
        public var openAutoClose: TimeInterval
        /// Pasar el mouse hace asomar a ORBEX.
        public var hoverPeeks: Bool

        public init(peekLinger: TimeInterval = 0.8, openAutoClose: TimeInterval = 15, hoverPeeks: Bool = true) {
            self.peekLinger = peekLinger
            self.openAutoClose = openAutoClose
            self.hoverPeeks = hoverPeeks
        }
    }

    public private(set) var state: IslandState = .hidden
    public private(set) var context = IslandContext()
    public private(set) var isHovering = false
    public var config: Config

    /// Se llama en cada cambio de estado: (anterior, nuevo).
    public var onChange: ((IslandState, IslandState) -> Void)?

    private var deadline: Date?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Momento en el que vence la espera actual (para pruebas / depuración).
    public var pendingDeadline: Date? { deadline }

    public func handle(_ event: IslandEvent, now: Date = Date()) {
        switch event {
        case .mouseEntered:
            isHovering = true
            deadline = nil
            if config.hoverPeeks, state == .hidden || state == .sleeping {
                set(.peek)
            }

        case .mouseExited:
            isHovering = false
            switch state {
            case .peek:
                deadline = now.addingTimeInterval(config.peekLinger)
            case .open:
                deadline = now.addingTimeInterval(config.openAutoClose)
            default:
                break
            }

        case .click:
            switch state {
            case .hidden, .peek, .active, .needsYou, .sleeping:
                deadline = nil
                set(.open)
            case .open, .assistant, .clock:
                break
            }

        case .clickOutside:
            // El asistente solo se cierra con Esc, el atajo o su botón: así no se pierde
            // lo que se está escribiendo por un clic accidental.
            if state == .open { goToRest() }

        case .escape:
            if state.isExpanded { goToRest() }

        case .open:
            deadline = nil
            if state != .open { set(.open) }
            if !isHovering { deadline = now.addingTimeInterval(config.openAutoClose) }

        case .close:
            if !state.isResting { goToRest() }

        case .toggleAssistant:
            if state == .assistant { goToRest() } else { deadline = nil; set(.assistant) }

        case .toggleClock:
            if state == .clock { goToRest() } else { deadline = nil; set(.clock) }

        case .contextChanged(let newContext):
            let hadAttention = context.needsAttention
            context = newContext
            if state.isResting {
                set(context.restingState)
            } else if state == .peek, context.needsAttention, !hadAttention {
                set(.needsYou)
            }
        }
    }

    /// Resuelve vencimientos. Llamar periódicamente (p. ej. cada 0,1 s).
    public func tick(now: Date = Date()) {
        guard let d = deadline, now >= d else { return }
        deadline = nil
        guard !isHovering else { return }
        if state == .peek || state == .open { goToRest() }
    }

    private func goToRest() {
        deadline = nil
        set(isHovering && config.hoverPeeks && context.restingState == .hidden ? .peek : context.restingState)
    }

    private func set(_ new: IslandState) {
        let old = state
        guard old != new else { return }
        state = new
        onChange?(old, new)
    }
}
