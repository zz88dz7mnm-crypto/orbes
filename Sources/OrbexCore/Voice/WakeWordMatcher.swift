import Foundation

/// Lo que se detectó al escuchar la palabra de activación ("Orbex, abrí Spotify").
public struct WakeMatch: Equatable, Sendable {
    /// La variante detectada, tal como vino ("Orbes", "Or bex", "Orbi"), sin signos de borde.
    public let wakeWord: String
    /// Lo dicho DESPUÉS de la palabra, sin comas ni puntos de borde (puede ser "").
    public let command: String
    /// Posición del nombre (en palabras) dentro de la transcripción. No cuenta para `==`.
    public let wordIndex: Int

    public init(wakeWord: String, command: String, wordIndex: Int = 0) {
        self.wakeWord = wakeWord
        self.command = command
        self.wordIndex = wordIndex
    }

    public static func == (a: WakeMatch, b: WakeMatch) -> Bool {
        a.wakeWord == b.wakeWord && a.command == b.command
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
        "orbeks", "orbecs", "orbeck", "orbek", "orvi", "orbez", "orvez",
    ]

    /// Todas las formas escritas que conviene sugerirle al reconocedor (`contextualStrings`).
    public static let recognizerHints: [String] = [
        "Orbex", "Orbi", "Orbes", "Orbis", "Orby", "Orvex", "Orbeks", "Orbeck", "Orvi", "Ok Orbi", "Hola Orbi",
        "Oye Orbi", "Orbi, pará", "Orbex, activá el modo inteligente", "modo inteligente",
    ]

    /// Palabras reales parecidas a un nombre que nunca activan por parecido (sí si están tal cual en `names`).
    static let lookalikes: Set<String> = [
        "orbit", "orbita", "orbitas", "orbital", "orbitar", "orbits", "orbitan", "orbitando", "orgy", "orly", "ores",
        "oribi", "ovis", "orbe",
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
    /// El nombre tiene que empezar la transcripción o una oración.
    public func match(_ transcript: String) -> WakeMatch? {
        find(transcript, allowed: { w, s in w[s].startsSentence }, glued: false)
    }

    /// Versión tolerante para "siempre atento" (esperando el nombre): además del principio de oración, acepta
    /// el nombre en las últimas `lastWords` palabras de lo oído (el reconocimiento continuo casi nunca pone
    /// puntos, así que el nombre suele quedar al final de lo que se venía oyendo) y el nombre pegado al pedido
    /// ("orbexabrí Spotify" → "abrí Spotify"). Sigue rechazando "órbita", "sorbete", "horno", "Forbes"…
    public func matchWaiting(_ transcript: String, lastWords: Int = 4) -> WakeMatch? {
        find(transcript, allowed: { w, s in w[s].startsSentence || s >= w.count - max(1, lastWords) }, glued: true)
    }

    /// Mientras se escucha el pedido: el mismo nombre detectado con `matchWaiting`, que ahora está cerca de
    /// la palabra `wordIndex` (las parciales se corrigen: se admite ±2 palabras) o al principio de una oración.
    public func match(_ transcript: String, near wordIndex: Int) -> WakeMatch? {
        find(transcript, allowed: { w, s in w[s].startsSentence || abs(s - wordIndex) <= 2 }, glued: true)
    }

    func find(_ transcript: String, allowed: ([Word], Int) -> Bool, glued: Bool) -> WakeMatch? {
        let w = Self.words(transcript)
        var result: WakeMatch?
        let trim = CommandText.edgePunctuation.union(.whitespacesAndNewlines)
        for s in w.indices where allowed(w, s) {
            var j = s
            var skipped = 0
            while skipped < 3, let g = Self.greetingLength(w, at: j), nameLength(w, at: j) == nil {
                j += g
                skipped += 1
            }
            guard j < w.count else { continue }
            if let n = nameLength(w, at: j) {
                var end = j + n
                // "Orbex, Orbex, abrí…": el nombre repetido no es parte del pedido.
                while let r = nameLength(w, at: end) { end += r }
                let wake = transcript[w[j].raw.startIndex..<w[j + n - 1].raw.endIndex]
                let rest = transcript[w[end - 1].raw.endIndex...]
                result = WakeMatch(wakeWord: String(wake).trimmingCharacters(in: trim),
                                   command: rest.trimmingCharacters(in: VoiceText.edgeTrim),
                                   wordIndex: j)
            } else if glued, let split = gluedSplit(w[j]) {
                let raw = w[j].raw
                let wake = transcript[raw.startIndex..<split]
                let rest = transcript[split...]
                result = WakeMatch(wakeWord: String(wake).trimmingCharacters(in: trim),
                                   command: rest.trimmingCharacters(in: VoiceText.edgeTrim),
                                   wordIndex: j)
            }
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
        let tail = Self.spelledLetters[b.key] ?? b.key
        guard !b.startsSentence, (1...4).contains(tail.count), let lastA = a.raw.last, lastA.isLetter else { return nil }
        let head = Self.variants(a.key).first { v in
            v.count >= 2 && keys.contains { $0.count > v.count && $0.hasPrefix(v) }
        }
        return head.map { $0 + tail }
    }

    /// Letras dichas por su nombre ("Orbe equis" → "orbex").
    static let spelledLetters: [String: String] = ["equis": "x", "ekis": "x", "ex": "ex", "ks": "x"]

    /// "Orbexabrí" → dónde termina el nombre dentro de la palabra (solo nombres de 5+ letras, y si queda un
    /// pedido de 3+ letras pegado). `nil` si la palabra no empieza con un nombre.
    func gluedSplit(_ word: Word) -> Substring.Index? {
        guard word.key.count >= 8, !Self.lookalikes.contains(word.key) else { return nil }
        for (v, extra) in zip(Self.variants(word.key), [0, 1]) {
            guard let name = keys.filter({ $0.count >= 5 && v.hasPrefix($0) && v.count - $0.count >= 3 })
                .max(by: { $0.count < $1.count }) else { continue }
            let letters = name.count + (Self.variants(word.key).count > 1 ? extra : 0)
            var seen = 0
            var i = word.raw.startIndex
            while i < word.raw.endIndex {
                if !VoiceText.key(String(word.raw[i])).isEmpty { seen += 1 }
                i = word.raw.index(after: i)
                if seen == letters { return i }
            }
        }
        return nil
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
