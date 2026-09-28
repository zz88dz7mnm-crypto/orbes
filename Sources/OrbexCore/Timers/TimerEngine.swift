import Foundation

/// Lo que pasó en un `tick`.
public enum TimerEvent: Equatable, Sendable {
    /// Un timer (o un pomodoro completo) terminó. `at` = hora real de fin (puede ser vieja si la app estuvo cerrada).
    case finished(id: UUID, label: String, at: Date)
    /// Un pomodoro pasó de fase (sigue corriendo).
    case pomodoroPhase(id: UUID, phase: Pomodoro.Phase, at: Date)
}

/// Todos los temporizadores + el cronómetro. Es `Codable`: la app lo guarda en disco tal cual.
public struct TimerEngine: Codable, Equatable, Sendable {
    public var timers: [OrbexTimer] = []
    public var stopwatch = Stopwatch()
    /// Un timer terminado queda "sonando" este tiempo y después se saca solo.
    public var autoDismissAfter: TimeInterval = 60

    public init() {}

    // MARK: - Consultas

    public func timer(_ id: UUID) -> OrbexTimer? { timers.first { $0.id == id } }

    /// Hay algo contando (timer corriendo o cronómetro andando).
    public var anyRunning: Bool { timers.contains { $0.isRunning } || stopwatch.isRunning }

    /// Hay algún timer terminado esperando que el usuario lo vea.
    public var anyRinging: Bool { timers.contains { $0.isFinished } }

    /// El timer corriendo que termina primero.
    public var nextToFinish: OrbexTimer? {
        timers.filter { $0.isRunning }.min { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    /// Próxima hora en que algo cambia (para programar el siguiente chequeo).
    public var nextDeadline: Date? { nextToFinish?.endDate }

    /// Línea corta para la isla: "⏱ Pizza 12:30", "🍅 Foco 1/4 24:10", "⏰ ¡Terminó Pizza!", "⏱ 03:12".
    public func statusLine(at now: Date) -> String {
        if let ringing = timers.first(where: { $0.isFinished }) {
            return "⏰ ¡Terminó \(ringing.displayName)!"
        }
        if let next = nextToFinish {
            let icon = next.pomodoro != nil ? "🍅" : "⏱"
            return "\(icon) \(next.displayName) \(TimerFormat.countdown(next.remaining(at: now)))"
        }
        if stopwatch.isRunning {
            return "⏱ \(TimerFormat.clock(stopwatch.elapsed(at: now)))"
        }
        if let paused = timers.first(where: { $0.isPaused }) {
            return "⏸ \(paused.displayName) \(TimerFormat.countdown(paused.remaining(at: now)))"
        }
        return ""
    }

    // MARK: - Timers

    @discardableResult
    public mutating func add(duration: TimeInterval, label: String? = nil, now: Date = Date()) -> OrbexTimer {
        let t = OrbexTimer(duration: duration, label: label, now: now)
        timers.append(t)
        return t
    }

    @discardableResult
    public mutating func startPomodoro(_ config: Pomodoro = Pomodoro(), now: Date = Date()) -> OrbexTimer {
        let t = OrbexTimer(duration: config.currentDuration, label: "Pomodoro", now: now, pomodoro: config)
        timers.append(t)
        return t
    }

    public mutating func pause(_ id: UUID, now: Date = Date()) {
        update(id) { $0.pause(at: now) }
    }

    public mutating func resume(_ id: UUID, now: Date = Date()) {
        update(id) { $0.resume(at: now) }
    }

    public mutating func togglePause(_ id: UUID, now: Date = Date()) {
        update(id) { t in
            if t.isRunning { t.pause(at: now) } else if t.isPaused { t.resume(at: now) }
        }
    }

    public mutating func addTime(_ id: UUID, seconds: TimeInterval, now: Date = Date()) {
        update(id) { $0.add(seconds, at: now) }
    }

    public mutating func restart(_ id: UUID, now: Date = Date()) {
        update(id) { $0.restart(at: now) }
    }

    public mutating func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    /// Saca los timers que ya sonaron.
    public mutating func dismissFinished() {
        timers.removeAll { $0.isFinished }
    }

    private mutating func update(_ id: UUID, _ change: (inout OrbexTimer) -> Void) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[i])
    }

    // MARK: - Tick

    /// Avanza el reloj: marca los timers vencidos, pasa de fase los pomodoros (poniéndose al día si la app
    /// estuvo cerrada) y saca los terminados hace más de `autoDismissAfter`.
    public mutating func tick(now: Date) -> [TimerEvent] {
        var events: [TimerEvent] = []
        for i in timers.indices {
            guard case .running(var end) = timers[i].state, end <= now else { continue }
            if var pomo = timers[i].pomodoro {
                var done = false
                // Ponerse al día: puede haber pasado más de una fase.
                while end <= now {
                    if pomo.advance() {
                        events.append(.pomodoroPhase(id: timers[i].id, phase: pomo.phase, at: end))
                        end = end.addingTimeInterval(pomo.currentDuration)
                    } else {
                        done = true
                        break
                    }
                }
                timers[i].pomodoro = pomo
                if done {
                    timers[i].state = .finished(at: end)
                    events.append(.finished(id: timers[i].id, label: "Pomodoro", at: end))
                } else {
                    timers[i].duration = pomo.currentDuration
                    timers[i].state = .running(endDate: end)
                }
            } else {
                timers[i].state = .finished(at: end)
                events.append(.finished(id: timers[i].id, label: timers[i].displayName, at: end))
            }
        }
        timers.removeAll { t in
            if case .finished(let at) = t.state { return now.timeIntervalSince(at) > autoDismissAfter }
            return false
        }
        return events
    }
}

/// Formatos de tiempo para timers y cronómetro.
public enum TimerFormat {
    /// Cuenta regresiva redondeada hacia arriba: 300 → "5:00", 4.2 → "0:05", 3725 → "1:02:05".
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(max(0, seconds).rounded(.up))
    }

    /// "m:ss" o "h:mm:ss" (redondeado hacia abajo).
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Cronómetro con décimas: "1:02,3".
    public static func stopwatch(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let tenths = Int((clamped * 10).rounded(.down)) % 10
        return "\(clock(clamped)),\(tenths)"
    }

    /// Duración en palabras: 300 → "5 min", 4800 → "1 h 20 min", 45 → "45 s".
    public static func words(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 && h == 0 { parts.append("\(s) s") }
        return parts.isEmpty ? "0 s" : parts.joined(separator: " ")
    }
}
