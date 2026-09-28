import Foundation

/// Recordatorio o acción programada (informe §9.6).
public struct ScheduledAction: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case reminder(text: String)
        case action(name: String)
    }

    public let id: UUID
    public var date: Date
    public var kind: Kind
    public let createdAt: Date
    public var done: Bool

    public init(id: UUID = UUID(), date: Date, kind: Kind, createdAt: Date = Date(), done: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.createdAt = createdAt
        self.done = done
    }

    /// Texto corto para listas: el recordatorio o el nombre de la acción.
    public var title: String {
        switch kind {
        case .reminder(let text): return text
        case .action(let name): return name
        }
    }
}

/// Qué hacer con lo que venció mientras la Mac dormía.
public enum MissedPolicy: String, Codable, CaseIterable, Sendable {
    /// Ejecutarlo al despertar.
    case runOnWake
    /// Solo avisar que se perdió.
    case notifyOnly
}

/// Lista de programados, sin reloj propio: quien la usa decide cuándo mirar.
public struct SchedulerEngine: Codable, Equatable, Sendable {
    public private(set) var actions: [ScheduledAction]

    public init(actions: [ScheduledAction] = []) {
        self.actions = actions.sorted { $0.date < $1.date }
    }

    public mutating func add(_ action: ScheduledAction) {
        actions.append(action)
        actions.sort { $0.date < $1.date }
    }

    public mutating func remove(id: UUID) {
        actions.removeAll { $0.id == id }
    }

    /// Pendientes cuya hora ya llegó.
    public func due(now: Date) -> [ScheduledAction] {
        actions.filter { !$0.done && $0.date <= now }
    }

    /// Pendientes que vencieron entre `since` (exclusivo) y `now` (p. ej. mientras dormía).
    public func missed(since: Date, now: Date) -> [ScheduledAction] {
        actions.filter { !$0.done && $0.date > since && $0.date <= now }
    }

    public mutating func markDone(id: UUID) {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[i].done = true
    }

    /// Borra los ya hechos anteriores a `date`.
    public mutating func purgeDone(before date: Date) {
        actions.removeAll { $0.done && $0.date < date }
    }

    public var pending: [ScheduledAction] { actions.filter { !$0.done } }
}
