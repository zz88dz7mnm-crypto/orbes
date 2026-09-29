import Foundation

// Cerebro de la personalidad de ORBEX: decide qué decir y qué gesto hacer a partir de datos del
// sistema que le pasa la app (segundos sin input, segundos sin teclas, cambio de app).
// No mira el sistema por su cuenta: es lógica pura y se prueba con fechas inventadas.

/// Hacia dónde mira ORBEX. `dx`: −1 izquierda … 1 derecha. `dy`: −1 arriba … 1 abajo.
/// El módulo (dx, dy) nunca pasa de 1.
public struct GazeVector: Equatable, Codable, Sendable {
    public var dx: Double
    public var dy: Double

    public static let ahead = GazeVector(dx: 0, dy: 0)
    /// Mirada hacia el teclado (abajo, apenas).
    public static let keyboard = GazeVector(dx: 0, dy: 0.6)

    public init(dx: Double, dy: Double) {
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 1 {
            self.dx = dx / len
            self.dy = dy / len
        } else {
            self.dx = dx
            self.dy = dy
        }
    }

    /// Dirección desde `origin` (dónde está ORBEX) hasta `target`, en coordenadas de pantalla con
    /// y hacia abajo. `reach`: distancia que equivale a mirar "del todo" (p. ej. media pantalla).
    public static func toward(originX: Double, originY: Double,
                              targetX: Double, targetY: Double, reach: Double) -> GazeVector {
        guard reach > 0 else { return .ahead }
        return GazeVector(dx: (targetX - originX) / reach, dy: (targetY - originY) / reach)
    }
}

/// Emotes que la personalidad pide (la app los traduce a los del motor).
public enum PersonalityEmote: String, Codable, Sendable {
    case love, happy, wink, surprised, proud, yawn
}

/// Lo que la app tiene que aplicar.
public enum PersonalityEvent: Equatable, Sendable {
    /// Nuevo texto del encabezado de la isla.
    case header(String)
    case emote(PersonalityEmote)
    case blink
    /// Escala de ojos (1 = normal; <1 atento/entrecerrado).
    case eyeScale(Double)
    /// Mirar hacia `GazeVector`. `duration` 0 = sostener hasta la próxima mirada.
    case glance(GazeVector, duration: Double)
}

/// Umbrales (todo en segundos).
public struct PersonalityConfig: Equatable, Sendable {
    /// Sin input durante esto = "se fue".
    public var awayThreshold: TimeInterval = 20 * 60
    /// Input más reciente que esto = "volvió".
    public var returnedWithin: TimeInterval = 5
    /// Tecla más reciente que esto = "está tipeando".
    public var typingWithin: TimeInterval = 1.5
    /// Sin teclas durante esto = "dejó de tipear".
    public var typingStopAfter: TimeInterval = 4
    /// Cada cuánto parpadea mientras te ve tipear.
    public var typingBlinkEvery: TimeInterval = 7
    /// Cada cuánto rota la frase del encabezado.
    public var rotateEvery: TimeInterval = 45
    /// Cuánto queda un mensaje especial (saludo, racha, "te extrañé") antes de rotar.
    public var messageHold: TimeInterval = 10
    /// Duración del vistazo a la app nueva.
    public var glanceDuration: TimeInterval = 0.9
    /// Separación mínima entre vistazos (cambios de app en ráfaga).
    public var glanceCooldown: TimeInterval = 1.5

    public init() {}
}

/// Estado persistente (va a UserDefaults en `orbex.personality.state`). Nada sensible.
public struct PersonalityRecord: Codable, Equatable, Sendable {
    /// Último día (inicio del día local) en que se usó ORBEX.
    public var lastUseDay: Date?
    /// Días seguidos de uso, contando `lastUseDay`.
    public var streakDays: Int = 0
    /// Último momento de uso registrado.
    public var lastSeen: Date?

    public init() {}

    /// Registra un uso en `now`. Devuelve `true` si es el primer uso del día.
    @discardableResult
    public mutating func registerUse(now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        lastSeen = now
        guard let last = lastUseDay else {
            lastUseDay = today
            streakDays = 1
            return true
        }
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
        if diff == 0 { return false }
        streakDays = diff == 1 ? max(1, streakDays) + 1 : 1
        lastUseDay = today
        return true
    }

    /// `true` si `now` cae en otro día que el último uso (o nunca se usó).
    public func isNewDay(now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastUseDay else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}

/// El cerebro: se alimenta con muestras del sistema y devuelve eventos.
public struct PersonalityBrain: Sendable {
    public var config: PersonalityConfig
    public private(set) var record: PersonalityRecord
    public private(set) var headerLine: String = ""
    public private(set) var isTyping = false
    public private(set) var isAway = false

    public var name: String

    private var rotator = PhraseRotator(memory: 4)
    private var pending: [String] = []
    private var holdUntil: Date = .distantPast
    private var lastRotation: Date = .distantPast
    private var lastBlink: Date = .distantPast
    private var lastGlance: Date = .distantPast
    private var glanceCount = 0
    private var longestIdle: TimeInterval = 0
    private var started = false

    public init(record: PersonalityRecord = PersonalityRecord(), name: String = "",
                config: PersonalityConfig = PersonalityConfig()) {
        self.record = record
        self.name = name
        self.config = config
    }

    // MARK: - Arranque

    /// Al abrir la app: saludo según la hora y, si hay, la racha de días.
    public mutating func start(now: Date, calendar: Calendar = .current) -> [PersonalityEvent] {
        started = true
        record.registerUse(now: now, calendar: calendar)
        greet(now: now, calendar: calendar)
        return flushHeader(now: now, calendar: calendar, forceRotate: true)
    }

    // MARK: - Muestra periódica

    /// Muestra del sistema. `idleSeconds`: segundos desde cualquier input. `keyIdleSeconds`: desde la
    /// última tecla.
    public mutating func tick(now: Date, idleSeconds: TimeInterval, keyIdleSeconds: TimeInterval,
                              calendar: Calendar = .current) -> [PersonalityEvent] {
        if !started { return start(now: now, calendar: calendar) }
        var events: [PersonalityEvent] = []

        // Ausencia larga → "¡Te extrañé!"
        if idleSeconds >= config.awayThreshold {
            isAway = true
            longestIdle = max(longestIdle, idleSeconds)
        } else if isAway, idleSeconds <= config.returnedWithin {
            isAway = false
            let minutes = Int(longestIdle / 60)
            longestIdle = 0
            let newDay = record.registerUse(now: now, calendar: calendar)
            // Primero el saludo (si cambió el día), después el "te extrañé" arriba de todo.
            if newDay { greet(now: now, calendar: calendar) }
            pending.insert(PersonalityPhrases.missedYou(name: name, awayMinutes: minutes), at: 0)
            holdUntil = .distantPast
            events.append(.emote(.love))
        } else if !isAway, idleSeconds <= config.returnedWithin, record.isNewDay(now: now, calendar: calendar) {
            // Pasó la medianoche con la app abierta y en uso.
            record.registerUse(now: now, calendar: calendar)
            greet(now: now, calendar: calendar)
        }

        // Te ve tipear.
        if !isTyping, keyIdleSeconds <= config.typingWithin {
            isTyping = true
            lastBlink = now
            events += [.glance(.keyboard, duration: 0), .eyeScale(0.94), .blink]
        } else if isTyping, keyIdleSeconds >= config.typingStopAfter {
            isTyping = false
            events += [.glance(.ahead, duration: 0), .eyeScale(1)]
        } else if isTyping, now.timeIntervalSince(lastBlink) >= config.typingBlinkEvery {
            lastBlink = now
            events.append(.blink)
        }

        events += flushHeader(now: now, calendar: calendar, forceRotate: false)
        return events
    }

    // MARK: - Cambio de app

    /// Se activó otra app. `toward`: dirección hacia su ventana (nil si no se sabe: mira de costado).
    public mutating func appActivated(now: Date, toward: GazeVector?) -> [PersonalityEvent] {
        guard now.timeIntervalSince(lastGlance) >= config.glanceCooldown else { return [] }
        lastGlance = now
        let dir = toward ?? GazeVector(dx: 0.5, dy: 0.3)
        var events: [PersonalityEvent] = [.glance(dir, duration: config.glanceDuration)]
        glanceCount += 1
        if glanceCount % 3 == 0 { events.append(.blink) }
        return events
    }

    // MARK: - Interno

    /// Encola el saludo del momento del día y, si hay, la racha.
    private mutating func greet(now: Date, calendar: Calendar) {
        pending.append(PersonalityPhrases.greeting(name: name, part: DayPart(date: now, calendar: calendar)))
        if let s = PersonalityPhrases.streak(days: record.streakDays) { pending.append(s) }
        holdUntil = .distantPast
    }

    private mutating func flushHeader(now: Date, calendar: Calendar, forceRotate: Bool) -> [PersonalityEvent] {
        guard now >= holdUntil else { return [] }
        if !pending.isEmpty {
            let line = pending.removeFirst()
            holdUntil = now.addingTimeInterval(config.messageHold)
            lastRotation = now
            return setHeader(line)
        }
        guard forceRotate || now.timeIntervalSince(lastRotation) >= config.rotateEvery else { return [] }
        lastRotation = now
        let pool = isTyping
            ? PersonalityPhrases.typing + PersonalityPhrases.general
            : PersonalityPhrases.pool(for: DayPart(date: now, calendar: calendar))
        guard let line = rotator.next(from: pool) else { return [] }
        return setHeader(line)
    }

    private mutating func setHeader(_ line: String) -> [PersonalityEvent] {
        guard line != headerLine else { return [] }
        headerLine = line
        return [.header(line)]
    }
}
