import Foundation

/// Utilidades de texto para lo que devuelve el reconocimiento de voz (español, con tildes, mayúsculas y
/// puntuación que cambian entre transcripciones parciales).
enum VoiceText {
    /// Solo letras, en minúsculas y sin tildes ("¡Or-bex!" → "orbex").
    static func key(_ s: String) -> String {
        CommandText.fold(s).filter { $0.isLetter }
    }

    /// Huella de lo dicho para comparar parciales: letras y números separados por un espacio, sin signos
    /// ni mayúsculas ("Abrí Spotify." y "abrí spotify" dan lo mismo).
    static func speechKey(_ s: String) -> String {
        CommandText.fold(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    /// ¿La palabra cierra una oración? ("Spotify." "¿sí?" "¡listo!" "bueno…").
    static func endsSentence(_ raw: Substring) -> Bool {
        var s = raw
        while let last = s.last, ")]}\"'»”’".contains(last) { s = s.dropLast() }
        guard let last = s.last else { return false }
        return ".?!…;".contains(last)
    }

    /// Bordes que sobran en un pedido: espacios, comas, puntos, guiones ("…, abrí Spotify." → "abrí Spotify").
    /// Los signos de pregunta y exclamación se dejan.
    static let edgeTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-–—…"))

    /// Cambia la palabra de `raw` por `word` conservando los signos pegados ("¿recordás" → "¿recordame").
    static func swapWord(_ raw: String, _ word: String) -> String {
        let chars = Array(raw)
        guard let first = chars.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = chars.lastIndex(where: { $0.isLetter || $0.isNumber }) else { return word }
        return String(chars[..<first]) + word + String(chars[(last + 1)...])
    }

    /// Distancia de edición (Levenshtein). Corta antes si ya supera `limit`.
    static func distance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
