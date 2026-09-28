import Foundation

/// Temporizador de cuenta regresiva. Guarda la **hora de fin** (no la cuenta) para sobrevivir a cerrar la
/// app y a reinicios (informe §9.5). En pausa guarda lo que falta.
public struct OrbexTimer: Codable, Equatable, Identifiable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }

    public let id: UUID
    public var label: String?
    /// Duración total de la vuelta actual (para el anillo).
    public var duration: TimeInterval
    public var state: State
    public let createdAt: Date
    /// Si es un pomodoro, su ciclo.
    public var pomodoro: Pomodoro?

    public init(id: UUID = UUID(), duration: TimeInterval, label: String? = nil, now: Date = Date(),
                pomodoro: Pomodoro? = nil) {
        self.id = id
        self.label = label
        self.duration = max(1, duration)
        self.state = .running(endDate: now.addingTimeInterval(max(1, duration)))
        self.createdAt = now
        self.pomodoro = pomodoro
    }

    // MARK: - Consultas

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    /// Hora de fin si está corriendo.
    public var endDate: Date? {
        if case .running(let end) = state { return end }
        return nil
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining): return max(0, remaining)
        case .finished: return 0
        }
    }

    /// Fracción que falta (1 = recién empezado, 0 = terminado). Para el anillo que se vacía.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }

    /// Nombre para mostrar: la etiqueta, la fase del pomodoro o "Timer".
    public var displayName: String {
        if let p = pomodoro {
            if isFinished { return "Pomodoro" }
            return p.phase == .focus ? "\(p.phase.title) \(p.focusNumber)/\(p.cycles)" : p.phase.title
        }
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return "Timer"
    }

    // MARK: - Cambios

    public mutating func pause(at now: Date) {
        guard case .running(let end) = state else { return }
        state = .paused(remaining: max(0, end.timeIntervalSince(now)))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = state else { return }
        state = .running(endDate: now.addingTimeInterval(max(0, remaining)))
    }

    /// Suma (o resta) tiempo. Si estaba terminado, vuelve a correr con ese tiempo.
    public mutating func add(_ seconds: TimeInterval, at now: Date) {
        switch state {
        case .running(let end):
            let newEnd = max(now, end.addingTimeInterval(seconds))
            state = .running(endDate: newEnd)
            duration = max(duration, newEnd.timeIntervalSince(now))
        case .paused(let remaining):
            let r = max(0, remaining + seconds)
            state = .paused(remaining: r)
            duration = max(duration, r)
        case .finished:
            guard seconds > 0 else { return }
            duration = seconds
            state = .running(endDate: now.addingTimeInterval(seconds))
        }
    }

    /// Vuelve a empezar con la misma duración.
    public mutating func restart(at now: Date) {
        state = .running(endDate: now.addingTimeInterval(duration))
    }
}
