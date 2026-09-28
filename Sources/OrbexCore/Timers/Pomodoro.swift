import Foundation

/// Ciclo pomodoro: 25 min de foco y 5 de descanso; después de 4 focos, un descanso largo de 15 y termina.
public struct Pomodoro: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable, CaseIterable {
        case focus, shortBreak, longBreak

        public var title: String {
            switch self {
            case .focus: return "Foco"
            case .shortBreak: return "Descanso"
            case .longBreak: return "Descanso largo"
            }
        }

        public var symbol: String {
            switch self {
            case .focus: return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer"
            case .longBreak: return "sofa"
            }
        }
    }

    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    /// Focos antes del descanso largo.
    public var cycles: Int
    public private(set) var phase: Phase = .focus
    /// Focos terminados en esta tanda.
    public private(set) var completedFocus: Int = 0

    public init(focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60,
                longBreak: TimeInterval = 15 * 60, cycles: Int = 4) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.cycles = max(1, cycles)
    }

    public func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }

    public var currentDuration: TimeInterval { duration(of: phase) }

    /// Número de foco en curso (1...cycles), para mostrar "Foco 2/4".
    public var focusNumber: Int { min(cycles, completedFocus + (phase == .focus ? 1 : 0)) }

    /// Pasa a la fase siguiente. Devuelve `false` si la tanda terminó (después del descanso largo).
    @discardableResult
    public mutating func advance() -> Bool {
        switch phase {
        case .focus:
            completedFocus += 1
            phase = completedFocus >= cycles ? .longBreak : .shortBreak
            return true
        case .shortBreak:
            phase = .focus
            return true
        case .longBreak:
            return false
        }
    }
}
