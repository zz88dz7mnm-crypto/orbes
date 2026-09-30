import Foundation

/// Prepara un texto para decirlo en voz alta: saca markdown, código, enlaces y emoji, y lo parte en
/// frases cortas para empezar a hablar enseguida.
enum SpeechText {
    /// Texto limpio para hablar (puede quedar vacío).
    static func clean(_ input: String) -> String {
        var s = input.replacingOccurrences(of: "\r\n", with: "\n")

        // Bloques de código: no se leen.
        s = replace(s, #"```[\s\S]*?(```|$)"#, with: " ")
        // Imágenes y enlaces markdown: queda el texto del enlace.
        s = replace(s, #"!\[[^\]]*\]\([^)]*\)"#, with: " ")
        s = replace(s, #"\[([^\]]+)\]\([^)]*\)"#, with: "$1")
        // Código en línea: si es corto se lee, si no, se saca.
        s = replace(s, #"`([^`\n]{1,24})`"#, with: "$1")
        s = replace(s, #"`[^`\n]*`"#, with: " ")
        // Direcciones web y mails sueltos.
        s = replace(s, #"https?://\S+"#, with: "el enlace")
        // Títulos, citas, viñetas y listas numeradas al principio de la línea.
        s = replace(s, #"(?m)^\s{0,3}#{1,6}\s*"#, with: "")
        s = replace(s, #"(?m)^\s*>\s?"#, with: "")
        s = replace(s, #"(?m)^\s*[-*+•]\s+"#, with: "")
        s = replace(s, #"(?m)^\s*\d{1,3}[.)]\s+"#, with: "")
        // Líneas de tabla y separadores.
        s = replace(s, #"(?m)^\s*\|?[\s:|-]{3,}\|?\s*$"#, with: "")
        s = s.replacingOccurrences(of: "|", with: ", ")
        // Énfasis: **x**, __x__, *x*, _x_, ~~x~~.
        s = replace(s, #"(\*\*|__|~~)(.+?)\1"#, with: "$2")
        s = replace(s, #"(?<![\w*])\*(?!\s)([^*\n]+?)\*(?!\w)"#, with: "$1")
        s = replace(s, #"(?<![\w_])_(?!\s)([^_\n]+?)_(?!\w)"#, with: "$1")
        s = s.replacingOccurrences(of: "*", with: "")

        s = stripEmoji(s)

        // Cada línea es una idea: si no termina en puntuación, se le pone un punto.
        let lines = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                guard let last = line.last else { return line }
                return ".!?…:;,".contains(last) ? line : line + "."
            }
        s = lines.joined(separator: " ")
        s = replace(s, #"\s{2,}"#, with: " ")
        s = replace(s, #"\s+([,.;:!?])"#, with: "$1")
        s = replace(s, #"([,.;:])\1+"#, with: "$1")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parte en frases; la primera queda sola (para arrancar rápido) y las siguientes se juntan hasta
    /// ~`maxLength` caracteres. Las frases muy largas se cortan en comas o espacios.
    static func chunks(_ text: String, maxLength: Int = 200) -> [String] {
        let sentences = splitSentences(text).flatMap { hardSplit($0, maxLength: maxLength) }
        guard !sentences.isEmpty else { return [] }
        var out: [String] = [sentences[0]]
        var current = ""
        for sentence in sentences.dropFirst() {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxLength {
                current += " " + sentence
            } else {
                out.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: - Internos

    private static func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let isEnd = ".!?…".contains(c)
            let nextIsSpace = i + 1 >= chars.count || chars[i + 1] == " "
            // "3.5" o "etc.)" no cortan; "Hola. ¿Qué tal?" sí.
            if isEnd && nextIsSpace {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 1 { result.append(trimmed); current = "" }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty {
            if rest.count <= 2, let last = result.popLast() {
                result.append(last + " " + rest)
            } else {
                result.append(rest)
            }
        }
        return result.filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    private static func hardSplit(_ sentence: String, maxLength: Int) -> [String] {
        guard sentence.count > maxLength else { return [sentence] }
        var parts: [String] = []
        var rest = Substring(sentence)
        while rest.count > maxLength {
            let window = rest.prefix(maxLength)
            let cut = window.lastIndex(where: { ",;:".contains($0) })
                ?? window.lastIndex(of: " ")
                ?? window.endIndex
            let end = cut == window.endIndex ? cut : rest.index(after: cut)
            let piece = rest[..<end].trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { parts.append(piece) }
            rest = rest[end...]
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    private static func stripEmoji(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            let v = scalar.value
            let p = scalar.properties
            if v == 0x200D || (0xFE00...0xFE0F).contains(v) || (0x1F3FB...0x1F3FF).contains(v)
                || (0xE0020...0xE007F).contains(v) || v == 0x20E3 {
                continue
            }
            // Dígitos, #, * y © son "emoji" técnicamente: se dejan.
            if p.isEmojiPresentation || (p.isEmoji && v > 0x238C) {
                scalars.append(" ")
                continue
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func replace(_ s: String, _ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
