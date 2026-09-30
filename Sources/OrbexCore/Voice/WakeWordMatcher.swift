import Foundation

/// Lo que se detectó al escuchar la palabra de activación ("Orbex, abrí Spotify").
public struct WakeMatch: Equatable, Sendable {
    /// La variante detectada, tal como vino ("Orbes", "Or bex", "Orbi"), sin signos de borde.
    public let wakeWord: String
    /// Lo dicho DESPUÉS de la palabra, sin comas ni puntos de borde (puede ser "").
    public let command: String

    public init(wakeWord: String, command: String) {
        self.wakeWord = wakeWord
        self.command = command
    }
}

/// Encuentra "Orbex" (y cómo lo transcribe mal el reconocimiento de voz) al principio de lo dicho.
///
/// Reglas:
/// - El nombre tiene que ir al principio de la transcripción o de una oración (después de ".", "?", "!",
///   "…" o un salto de línea), con saludos opcionales delante ("hola", "oye", "che", "eh", "hey", "ok"…).
///   "abrí Spotify, Orbex" o "le dije a Orbex que…" no activan.
/// - Tolera tildes, mayúsculas, puntuación, una "h" muda delante ("Horbi") y el nombre partido en dos
///   ("Or bex", "Orbe X").
/// - En nombres de 4+ letras acepta `maxDistance` errores de edición ("Orbexs", "Orvix"), siempre que empiece
///   con la misma letra y no sea una palabra real parecida ("órbita", "orbit").
/// - Si hay varias oraciones que empiezan con el nombre, vale la última (el pedido más nuevo).
public struct WakeWordMatcher: Sendable {
    public static let defaultNames: [String] = [
        "orbex", "orbes", "orbis", "orbi", "orby", "orbix", "orbe",
        "orvex", "orves", "orvis",
        "orbeks", "orbecs", "orbeck", "orbek",
    ]

    /// Palabras reales parecidas a un nombre que nunca activan por parecido (sí si están tal cual en `names`).
    static let lookalikes: Set<String> = [
        "orbit", "orbita", "orbitas", "orbital", "orbitar", "orgy", "orly", "ores", "oribi", "ovis",
    ]

    /// Saludos que pueden ir antes del nombre ("hola Orbi", "oye, che, Orbex").
    static let greetings: [[String]] = [
        ["hola"], ["ola"], ["holi"], ["oye"], ["oie"], ["oiga"], ["che"], ["eh"], ["ey"], ["hey"], ["ei"],
        ["ok"], ["okay"], ["okey"], ["bueno"], ["buenas"], ["dale"], ["mira"], ["epa"], ["hi"], ["hello"],
        ["a", "ver"], ["buen", "dia"], ["buenos", "dias"], ["buenas", "tardes"], ["buenas", "noches"],
    ]

    public let names: [String]
    public let maxDistance: Int
    let keys: [String]
    let keySet: Set<String>

    public init(names: [String] = WakeWordMatcher.defaultNames, maxDistance: Int = 1) {
        self.names = names
        self.maxDistance = max(0, maxDistance)
        let k = names.map(VoiceText.key).filter { !$0.isEmpty }
        keySet = Set(k)
        keys = Array(keySet).sorted()
    }

    /// Busca la palabra de activación en una transcripción (tolerante a acentos, mayúsculas, puntuación,
    /// "hola/oye/che/eh" delante, palabra partida "or bex", y a 1 error de edición en nombres de 4+ letras).
    public func match(_ transcript: String) -> WakeMatch? {
        let w = Self.words(transcript)
        var result: WakeMatch?
        for s in w.indices where w[s].startsSentence {
            var j = s
            var skipped = 0
            while skipped < 3, let g = Self.greetingLength(w, at: j) {
                j += g
                skipped += 1
            }
            guard let n = nameLength(w, at: j) else { continue }
            var end = j + n
            // "Orbex, Orbex, abrí…": el nombre repetido no es parte del pedido.
            while let r = nameLength(w, at: end) { end += r }
            let wake = transcript[w[j].raw.startIndex..<w[j + n - 1].raw.endIndex]
            let rest = transcript[w[end - 1].raw.endIndex...]
            result = WakeMatch(
                wakeWord: String(wake).trimmingCharacters(in: CommandText.edgePunctuation.union(.whitespacesAndNewlines)),
                command: rest.trimmingCharacters(in: VoiceText.edgeTrim)
            )
        }
        return result
    }

    // MARK: - Palabras

    struct Word {
        let raw: Substring
        let key: String
        let startsSentence: Bool
    }

    static func words(_ s: String) -> [Word] {
        var out: [Word] = []
        var prevEnd = s.startIndex
        var newSentence = true
        for part in s.split(whereSeparator: { $0.isWhitespace }) {
            let gapHasNewline = s[prevEnd..<part.startIndex].contains(where: { $0.isNewline })
            prevEnd = part.endIndex
            let key = VoiceText.key(String(part))
            if key.isEmpty {
                // Signos sueltos ("—", "…", "?"): no son palabra, pero pueden cerrar la oración.
                if VoiceText.endsSentence(part) || gapHasNewline { newSentence = true }
                continue
            }
            out.append(Word(raw: part, key: key, startsSentence: newSentence || gapHasNewline))
            newSentence = VoiceText.endsSentence(part)
        }
        return out
    }

    static func greetingLength(_ w: [Word], at j: Int) -> Int? {
        greetings.filter { phrase in
            j + phrase.count <= w.count && phrase.enumerated().allSatisfy { w[j + $0.offset].key == $0.element }
        }.map(\.count).max()
    }

    // MARK: - Nombre

    /// Cuántas palabras ocupa el nombre en `w[j]` (1, o 2 si vino partido), o `nil`.
    func nameLength(_ w: [Word], at j: Int) -> Int? {
        guard j < w.count else { return nil }
        let joined = j + 1 < w.count ? joinedKey(w[j], w[j + 1]) : nil
        if let jn = joined, isExact(jn) { return 2 }
        if isExact(w[j].key) { return 1 }
        if isFuzzy(w[j].key) { return 1 }
        if let jn = joined, jn.count >= 5, isFuzzy(jn) { return 2 }
        return nil
    }

    /// "Or bex" → "orbex", "Orbe X" → "orbex", "Hor bis" → "orbis". Solo si la primera parte es el
    /// comienzo de un nombre y la segunda es corta.
    func joinedKey(_ a: Word, _ b: Word) -> String? {
        guard !b.startsSentence, (1...4).contains(b.key.count), let lastA = a.raw.last, lastA.isLetter else { return nil }
        let head = Self.variants(a.key).first { v in
            v.count >= 2 && keys.contains { $0.count > v.count && $0.hasPrefix(v) }
        }
        return head.map { $0 + b.key }
    }

    /// La palabra y, si empieza con "h" muda, sin ella ("horbi" → "orbi").
    static func variants(_ key: String) -> [String] {
        key.count > 1 && key.hasPrefix("h") ? [key, String(key.dropFirst())] : [key]
    }

    func isExact(_ key: String) -> Bool {
        Self.variants(key).contains { keySet.contains($0) }
    }

    func isFuzzy(_ key: String) -> Bool {
        guard maxDistance > 0 else { return false }
        for v in Self.variants(key) where v.count >= 4 && !Self.lookalikes.contains(v) {
            for name in keys where name.count >= 4 && name.first == v.first {
                if VoiceText.distance(v, name, limit: maxDistance) <= maxDistance { return true }
            }
        }
        return false
    }
}
