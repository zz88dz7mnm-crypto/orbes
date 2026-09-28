import Foundation

/// Una palabra del pedido: tal como la escribió el usuario (`raw`) y normalizada para comparar (`norm`:
/// minúsculas, sin tildes, sin signos de puntuación en los bordes).
struct CommandToken: Equatable {
    let raw: String
    let norm: String
}

/// Utilidades de texto del intérprete de comandos (español, tolerante a tildes y mayúsculas).
enum CommandText {
    static let edgePunctuation = CharacterSet(charactersIn: ",.;:!?¡¿\"'()[]{}«»“”‘’…-–—")
    static let payloadTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—\"'«»“”"))

    /// Minúsculas y sin tildes ("Cronómetro" → "cronometro"; la ñ queda como n).
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                  locale: Locale(identifier: "es")).lowercased()
    }

    /// Separa "nota:comprar pan" → "nota: comprar pan" (sin romper "9:30" ni "https://").
    static func preprocess(_ text: String) -> String {
        var out = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            out.append(c)
            if c == ":", i > 0, chars[i - 1].isLetter, i + 1 < chars.count {
                let next = chars[i + 1]
                if !next.isWhitespace && !next.isNumber && next != "/" { out.append(" ") }
            }
        }
        return out
    }

    static func tokenize(_ text: String) -> [CommandToken] {
        preprocess(text).split(whereSeparator: { $0.isWhitespace }).compactMap { part in
            let raw = String(part)
            let norm = fold(raw).trimmingCharacters(in: edgePunctuation)
            return norm.isEmpty ? nil : CommandToken(raw: raw, norm: norm)
        }
    }

    // MARK: - Relleno

    /// Frases de relleno al principio ("che", "porfa", "podés", "quiero que"...).
    static let leadingFillers: [[String]] = [
        ["por", "favor"], ["quiero", "que"], ["necesito", "que"], ["quisiera", "que"],
        ["me", "podes"], ["me", "podrias"], ["me", "puedes"], ["podes"], ["podrias"], ["puedes"],
        ["che"], ["orbex"], ["hey"], ["ey"], ["oye"], ["hola"], ["dale"], ["bueno"], ["porfa"], ["porfis"],
        ["ok"], ["okay"], ["listo"], ["ahora"], ["me"], ["vos"],
    ]

    /// Frases de relleno al final ("por favor", "gracias"...).
    static let trailingFillers: [[String]] = [
        ["por", "favor"], ["porfa"], ["porfis"], ["gracias"], ["please"], ["dale"],
    ]

    /// Saca el relleno del principio y del final.
    static func clean(_ tokens: [CommandToken]) -> [CommandToken] {
        var t = tokens
        var changed = true
        while changed && !t.isEmpty {
            changed = false
            for phrase in leadingFillers where hasPrefix(t, phrase) && t.count > phrase.count {
                t.removeFirst(phrase.count)
                changed = true
                break
            }
        }
        changed = true
        while changed && !t.isEmpty {
            changed = false
            for phrase in trailingFillers where hasSuffix(t, phrase) && t.count > phrase.count {
                t.removeLast(phrase.count)
                changed = true
                break
            }
        }
        return t
    }

    static func hasPrefix(_ t: [CommandToken], _ phrase: [String], at start: Int = 0) -> Bool {
        guard start >= 0, t.count - start >= phrase.count else { return false }
        for (k, w) in phrase.enumerated() where t[start + k].norm != w { return false }
        return true
    }

    static func hasSuffix(_ t: [CommandToken], _ phrase: [String]) -> Bool {
        hasPrefix(t, phrase, at: t.count - phrase.count)
    }

    /// Si `t` empieza con alguna de las frases, devuelve cuántas palabras ocupa (la más larga).
    static func matchPrefix(_ t: [CommandToken], _ phrases: [[String]], at start: Int = 0) -> Int? {
        phrases.filter { hasPrefix(t, $0, at: start) }.map(\.count).max()
    }

    // MARK: - Recortes

    static let articles: Set<String> = ["el", "la", "los", "las", "un", "una", "unos", "unas", "mi", "mis", "tu", "tus"]

    /// Saca palabras del principio mientras estén en `words`.
    static func dropLeading(_ t: [CommandToken], _ words: Set<String>) -> [CommandToken] {
        Array(t.drop(while: { words.contains($0.norm) }))
    }

    /// Saca palabras del final mientras estén en `words`.
    static func dropTrailing(_ t: [CommandToken], _ words: Set<String>) -> [CommandToken] {
        var out = t
        while let last = out.last, words.contains(last.norm) { out.removeLast() }
        return out
    }

    /// Une las palabras originales y limpia los bordes.
    static func join(_ t: [CommandToken]) -> String {
        var s = t.map(\.raw).joined(separator: " ").trimmingCharacters(in: payloadTrim)
        while let last = s.last, ".!¡?¿…".contains(last) {
            // Un "?" final solo se saca si no hay "¿" (sería parte de la pregunta).
            if last == "?" && s.contains("¿") { break }
            s.removeLast()
        }
        while let first = s.first, "¡¿".contains(first), !s.contains("?"), !s.contains("!") { s.removeFirst() }
        return s.trimmingCharacters(in: payloadTrim)
    }

    /// Primera letra en mayúscula ("pizza" → "Pizza").
    static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
