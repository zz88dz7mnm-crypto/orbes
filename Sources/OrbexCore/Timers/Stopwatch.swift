import Foundation

/// Cronómetro con vueltas. Guarda la hora de arranque, así sigue contando aunque la app se cierre.
public struct Stopwatch: Codable, Equatable, Sendable {
    public struct Lap: Equatable, Sendable, Identifiable {
        /// 1, 2, 3...
        public let number: Int
        /// Lo que duró esta vuelta.
        public let duration: TimeInterval
        /// Tiempo total al marcarla.
        public let total: TimeInterval
        public var id: Int { number }
    }

    /// Hora de arranque de la tanda actual (nil = en pausa o sin arrancar).
    public private(set) var startDate: Date?
    /// Tiempo acumulado antes de la tanda actual.
    public private(set) var accumulated: TimeInterval = 0
    /// Tiempo total en cada vuelta marcada.
    public private(set) var lapMarks: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { startDate != nil }

    /// Arrancado alguna vez y sin reiniciar.
    public var hasStarted: Bool { isRunning || accumulated > 0 || !lapMarks.isEmpty }

    public func elapsed(at now: Date) -> TimeInterval {
        guard let start = startDate else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(start))
    }

    /// Tiempo de la vuelta en curso.
    public func currentLap(at now: Date) -> TimeInterval {
        elapsed(at: now) - (lapMarks.last ?? 0)
    }

    /// Vueltas marcadas, la más nueva primero.
    public var laps: [Lap] {
        var out: [Lap] = []
        var previous: TimeInterval = 0
        for (i, mark) in lapMarks.enumerated() {
            out.append(Lap(number: i + 1, duration: mark - previous, total: mark))
            previous = mark
        }
        return out.reversed()
    }

    public mutating func start(at now: Date) {
        guard startDate == nil else { return }
        startDate = now
    }

    public mutating func pause(at now: Date) {
        guard let start = startDate else { return }
        accumulated += max(0, now.timeIntervalSince(start))
        startDate = nil
    }

    public mutating func toggle(at now: Date) {
        if isRunning { pause(at: now) } else { start(at: now) }
    }

    /// Marca una vuelta (solo corriendo). Devuelve lo que duró.
    @discardableResult
    public mutating func lap(at now: Date) -> TimeInterval? {
        guard isRunning else { return nil }
        let total = elapsed(at: now)
        let duration = total - (lapMarks.last ?? 0)
        lapMarks.append(total)
        return duration
    }

    public mutating func reset() {
        startDate = nil
        accumulated = 0
        lapMarks = []
    }
}
