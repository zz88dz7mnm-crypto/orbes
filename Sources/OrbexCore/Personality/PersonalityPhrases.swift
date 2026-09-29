import Foundation

// Personalidad de ORBEX: frases, saludos y momento del día (lógica pura, sin AppKit).

/// Momento del día según la hora local.
public enum DayPart: String, Codable, CaseIterable, Sendable {
    case madrugada   // 0–5
    case manana      // 6–12
    case tarde       // 13–19
    case noche       // 20–23

    public init(hour: Int) {
        switch hour {
        case 0..<6: self = .madrugada
        case 6..<13: self = .manana
        case 13..<20: self = .tarde
        default: self = .noche
        }
    }

    public init(date: Date, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: date))
    }
}

/// Textos de ORBEX en español rioplatense.
public enum PersonalityPhrases {
    /// Primer nombre a partir del nombre completo ("Juan Pedro Ameijeiras" → "Juan").
    /// Vacío si no hay nada usable.
    public static func firstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "." }).first else {
            return ""
        }
        return String(first)
    }

    /// "Buen día, Juan" / "Buenas tardes" (sin nombre si no hay).
    public static func greeting(name: String, part: DayPart) -> String {
        let base: String
        switch part {
        case .madrugada: base = "Buenas noches"
        case .manana: base = "Buen día"
        case .tarde: base = "Buenas tardes"
        case .noche: base = "Buenas noches"
        }
        return name.isEmpty ? base : "\(base), \(name)"
    }

    /// Mensaje al volver tras una ausencia larga.
    public static func missedYou(name: String, awayMinutes: Int) -> String {
        if awayMinutes >= 180 {
            return name.isEmpty ? "¡Volviste! Te extrañé" : "¡Volviste, \(name)! Te extrañé"
        }
        return name.isEmpty ? "¡Te extrañé!" : "¡Te extrañé, \(name)!"
    }

    /// Mensaje de racha: "3.º día seguido usando ORBEX". `nil` si la racha es de un día.
    public static func streak(days: Int) -> String? {
        guard days >= 2 else { return nil }
        return "\(days).º día seguido usando ORBEX"
    }

    /// Frases cortas que valen a cualquier hora.
    public static let general: [String] = [
        "Acá estoy, tranqui",
        "¿En qué andamos?",
        "Todo en orden por acá",
        "Si me necesitás, chiflá",
        "Vamos que se puede",
        "Un mate y seguimos",
        "Te hago el aguante",
        "Mirando de reojo…",
        "Nada se me escapa",
        "¿Arrancamos algo nuevo?",
    ]

    /// Frases según el momento del día.
    public static func phrases(for part: DayPart) -> [String] {
        switch part {
        case .madrugada:
            return ["Es tardísimo, ¿eh?", "La compu también duerme, ¿sabías?", "Un ratito más y a la cama"]
        case .manana:
            return ["Arrancando el día", "Café en mano, ¿no?", "Mañana productiva"]
        case .tarde:
            return ["¿Una pausa para estirar?", "Tarde tranqui", "Vamos bien, eh"]
        case .noche:
            return ["Ya es de noche, cuidate", "Última tanda y a descansar", "Nochecita de laburo"]
        }
    }

    /// Todas las frases disponibles para un momento del día (generales + propias).
    public static func pool(for part: DayPart) -> [String] {
        general + phrases(for: part)
    }

    /// Frase corta cuando el usuario está tipeando.
    public static let typing: [String] = ["Te veo tipear…", "Dale que va", "Escribís rápido, eh"]
}

/// Elige frases al azar sin repetir las últimas `memory` elegidas.
public struct PhraseRotator: Sendable {
    public let memory: Int
    public private(set) var recent: [String] = []

    public init(memory: Int = 3) {
        self.memory = max(1, memory)
    }

    /// Próxima frase del `pool`. `random(n)` devuelve un índice en 0..<n (inyectable para pruebas).
    public mutating func next(from pool: [String], random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String? {
        let unique = pool.reduce(into: [String]()) { acc, s in if !acc.contains(s) { acc.append(s) } }
        guard !unique.isEmpty else { return nil }
        // Nunca excluir todo: como mucho, todas menos una.
        let keep = min(memory, unique.count - 1)
        let excluded = Set(recent.suffix(keep))
        let candidates = unique.filter { !excluded.contains($0) }
        let pick = candidates[min(max(0, random(candidates.count)), candidates.count - 1)]
        recent.append(pick)
        if recent.count > memory { recent.removeFirst(recent.count - memory) }
        return pick
    }
}
