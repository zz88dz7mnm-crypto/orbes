import Foundation

/// Poses del cuerpo (hoja del personaje + estados del informe §4.4).
public enum Pose: String, CaseIterable, Codable, Sendable {
    case idle        // neutral
    case wave        // saludando
    case walk        // caminando en el lugar (trabajando)
    case crouch      // agachado (dormido)
    case dance       // bailando (música)
    case celebrate   // salto feliz (terminó algo)
    case worried     // se preocupa (falló algo)
    case focused     // concentrado (temporizador)
}

/// Variantes de color del personaje (hoja del personaje).
public enum OrbexTint: String, CaseIterable, Codable, Sendable {
    case clear, orange, green, violet

    /// Color base (RGB 0–1).
    public var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .clear:  return (0.84, 0.89, 0.94)
        case .orange: return (0.95, 0.63, 0.29)
        case .green:  return (0.55, 0.72, 0.42)
        case .violet: return (0.69, 0.49, 0.91)
        }
    }

    public var label: String {
        switch self {
        case .clear: return "Transparente"
        case .orange: return "Naranja"
        case .green: return "Verde"
        case .violet: return "Violeta"
        }
    }
}

/// Reacción al toque (informe §4.6): un clic = se achata y se molesta; 3 clics rápidos = se marea.
public struct TapTracker: Sendable {
    public enum Reaction: Equatable, Sendable { case squish, dizzy }

    public var window: Double = 1.2
    public var dizzyTaps: Int = 3
    private var taps: [Double] = []

    public init() {}

    public mutating func tap(at t: Double) -> Reaction {
        taps = taps.filter { t - $0 <= window }
        taps.append(t)
        if taps.count >= dizzyTaps {
            taps.removeAll()
            return .dizzy
        }
        return .squish
    }
}

/// Horario de sueño (capa L3: de noche se pone soñoliento).
public struct SleepPolicy: Equatable, Codable, Sendable {
    public var enabled: Bool
    /// Hora de dormir y de despertar (0–23). Si `start > end` cruza la medianoche.
    public var startHour: Int
    public var endHour: Int
    /// Minutos de inactividad del usuario para dormirse (0 = nunca por inactividad).
    public var idleMinutes: Int

    public init(enabled: Bool = true, startHour: Int = 23, endHour: Int = 7, idleMinutes: Int = 20) {
        self.enabled = enabled
        self.startHour = startHour
        self.endHour = endHour
        self.idleMinutes = idleMinutes
    }

    public func isNight(hour: Int) -> Bool {
        guard enabled, startHour != endHour else { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }

    public func shouldSleep(hour: Int, idleSeconds: Double) -> Bool {
        guard enabled else { return false }
        if isNight(hour: hour) { return true }
        return idleMinutes > 0 && idleSeconds >= Double(idleMinutes) * 60
    }
}

/// Saludo según la hora (capa L4: personalidad).
public enum Greeting {
    public static func text(hour: Int, name: String? = nil) -> String {
        let base: String
        switch hour {
        case 5..<12: base = "¡Buen día"
        case 12..<20: base = "¡Buenas tardes"
        default: base = "¡Buenas noches"
        }
        if let name, !name.isEmpty { return "\(base), \(name)!" }
        return "\(base)!"
    }
}

/// Decide pose y expresión "de fondo" según el estado de la isla y el contexto.
/// Los eventos puntuales (clic, microgesto, sorpresa) se superponen en la app.
public enum CharacterDirector {
    public struct Mood: Equatable, Sendable {
        public var pose: Pose
        public var expression: FaceExpression
        public init(pose: Pose, expression: FaceExpression) {
            self.pose = pose
            self.expression = expression
        }
    }

    public static func mood(for state: IslandState, isPlayingMusic: Bool = false,
                            hasTimerRunning: Bool = false) -> Mood {
        switch state {
        case .sleeping: return Mood(pose: .crouch, expression: .sleepy)
        case .needsYou: return Mood(pose: .wave, expression: .surprised)
        case .active:   return Mood(pose: .walk, expression: .focused)
        case .assistant: return Mood(pose: .idle, expression: .neutral)
        case .peek, .hidden, .open, .clock:
            if isPlayingMusic { return Mood(pose: .dance, expression: .happy) }
            if hasTimerRunning { return Mood(pose: .focused, expression: .focused) }
            return Mood(pose: .idle, expression: .neutral)
        }
    }
}
