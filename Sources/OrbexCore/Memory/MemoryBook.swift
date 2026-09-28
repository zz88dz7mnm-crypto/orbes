import Foundation

/// Un dato que ORBEX recuerda del usuario (informe §9.7).
public struct MemoryFact: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Memoria local y editable. Sin duplicados (ignora mayúsculas, tildes y espacios de más).
public struct MemoryBook: Codable, Equatable, Sendable {
    public private(set) var facts: [MemoryFact]

    public init(facts: [MemoryFact] = []) { self.facts = facts }

    public static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es"))
            .split(whereSeparator: { $0.isWhitespace || $0 == "." })
            .joined(separator: " ")
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public func contains(_ text: String) -> Bool {
        let k = Self.key(text)
        return facts.contains { Self.key($0.text) == k }
    }

    /// Agrega el dato; devuelve `false` si está vacío o ya existía.
    @discardableResult
    public mutating func add(_ text: String, now: Date = Date()) -> Bool {
        let t = Self.clean(text)
        guard !t.isEmpty, !contains(t) else { return false }
        facts.append(MemoryFact(text: t, createdAt: now))
        return true
    }

    /// Cambia el texto; si queda vacío lo borra. `false` si choca con otro dato.
    @discardableResult
    public mutating func edit(id: UUID, text: String) -> Bool {
        guard let i = facts.firstIndex(where: { $0.id == id }) else { return false }
        let t = Self.clean(text)
        if t.isEmpty { facts.remove(at: i); return true }
        let k = Self.key(t)
        if facts.contains(where: { $0.id != id && Self.key($0.text) == k }) { return false }
        facts[i].text = t
        return true
    }

    public mutating func delete(id: UUID) {
        facts.removeAll { $0.id == id }
    }

    public mutating func clearAll() { facts.removeAll() }
}
