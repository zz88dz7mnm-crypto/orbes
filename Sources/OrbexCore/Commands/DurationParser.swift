import Foundation

/// Números escritos en cifras o en palabras ("5", "1,5", "veinte", "treinta y cinco", "un", "una").
enum SpanishNumber {
    static let words: [String: Double] = [
        "cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
        "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12,
        "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16, "diecisiete": 17,
        "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiun": 21, "veintiuno": 21,
        "veintiuna": 21, "veintidos": 22, "veintitres": 23, "veinticuatro": 24,
        "veinticinco": 25, "veintiseis": 26, "veintisiete": 27, "veintiocho": 28,
        "veintinueve": 29, "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
        "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
    ]

    /// Número en cifras: "5", "25", "1,5", "1.5".
    static func digits(_ s: String) -> Double? {
        guard let first = s.first, first.isASCII, first.isNumber else { return nil }
        guard s.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." }) else { return nil }
        guard s.filter({ $0 == "," || $0 == "." }).count <= 1, s.last != ",", s.last != "." else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }

    /// Lee un número desde `t[i]`. Devuelve el valor y el índice siguiente.
    static func read(_ t: [CommandToken], at i: Int) -> (value: Double, next: Int)? {
        guard i >= 0, i < t.count else { return nil }
        let w = t[i].norm
        if let d = digits(w) { return (d, i + 1) }
        guard let v = words[w] else { return nil }
        // "treinta y cinco", "cuarenta y dos"
        if v >= 30, v < 100, v.truncatingRemainder(dividingBy: 10) == 0,
           i + 2 < t.count, t[i + 1].norm == "y", let u = words[t[i + 2].norm], u >= 1, u <= 9 {
            return (v + u, i + 3)
        }
        return (v, i + 1)
    }
}

/// Duraciones en español: "5 minutos", "1 hora y 20", "media hora", "un cuarto de hora",
/// "2 horas y media", "hora y media", "90 segundos", "1h20", "5min".
enum DurationParser {
    static let units: [String: Double] = [
        "segundo": 1, "segundos": 1, "seg": 1, "segs": 1, "s": 1, "sec": 1, "secs": 1,
        "minuto": 60, "minutos": 60, "minutito": 60, "minutitos": 60, "min": 60, "mins": 60, "m": 60,
        "hora": 3600, "horas": 3600, "horita": 3600, "horitas": 3600, "h": 3600, "hs": 3600,
        "hr": 3600, "hrs": 3600,
    ]

    /// Forma compacta en una sola palabra: "90s", "5min", "2hs", "1h20", "1h20m".
    /// Devuelve los segundos y la unidad más chica usada.
    static func compact(_ s: String) -> (seconds: Double, unit: Double)? {
        var total = 0.0
        var lastUnit: Double?
        var idx = s.startIndex
        while idx < s.endIndex {
            var num = ""
            while idx < s.endIndex, (s[idx].isASCII && s[idx].isNumber) || s[idx] == "." || s[idx] == "," {
                num.append(s[idx])
                idx = s.index(after: idx)
            }
            guard let n = SpanishNumber.digits(num) else { return nil }
            var unitName = ""
            while idx < s.endIndex, s[idx].isLetter {
                unitName.append(s[idx])
                idx = s.index(after: idx)
            }
            if unitName.isEmpty {
                // "1h20": el número final va en la unidad siguiente (minutos).
                guard let lu = lastUnit, lu > 1, idx == s.endIndex else { return nil }
                total += n * lu / 60
                lastUnit = lu / 60
                break
            }
            guard let u = units[unitName] else { return nil }
            total += n * u
            lastUnit = u
        }
        guard let lu = lastUnit, total > 0 else { return nil }
        return (total, lu)
    }

    /// Un término: "5 minutos", "media hora", "un cuarto de hora", "tres cuartos de hora", "1h20",
    /// o "hora" sola si sigue "y media"/"y cuarto".
    static func term(_ t: [CommandToken], at i: Int) -> (seconds: Double, unit: Double, next: Int)? {
        guard i >= 0, i < t.count else { return nil }
        func word(_ k: Int) -> String? { k >= 0 && k < t.count ? t[k].norm : nil }
        func unit(_ k: Int) -> Double? { word(k).flatMap { units[$0] } }
        let w = t[i].norm

        if let c = compact(w) { return (c.seconds, c.unit, i + 1) }
        if w == "media" || w == "medio", let u = unit(i + 1) { return (u / 2, u, i + 2) }

        // "un cuarto de hora", "cuarto de hora", "tres cuartos de hora"
        var k = i
        var mult = 1.0
        if let n = SpanishNumber.read(t, at: i), let nw = word(n.next), nw == "cuarto" || nw == "cuartos" {
            mult = n.value
            k = n.next
        }
        if let cw = word(k), cw == "cuarto" || cw == "cuartos", word(k + 1) == "de",
           let hw = word(k + 2), hw == "hora" || hw == "horas" {
            return (mult * 900, 3600, k + 3)
        }

        if let n = SpanishNumber.read(t, at: i), let u = unit(n.next), n.value > 0 {
            return (n.value * u, u, n.next + 1)
        }

        if w == "hora", word(i + 1) == "y", let nw = word(i + 2), nw == "media" || nw == "cuarto" {
            return (3600, 3600, i + 1)
        }
        return nil
    }

    /// Lee una duración completa desde `t[start]`. Devuelve los segundos y el índice siguiente.
    static func parse(_ t: [CommandToken], at start: Int) -> (seconds: Double, next: Int)? {
        guard var current = term(t, at: start) else { return nil }
        var total = current.seconds
        var i = current.next
        func word(_ k: Int) -> String? { k >= 0 && k < t.count ? t[k].norm : nil }

        while i < t.count {
            let w = t[i].norm
            if w == "y" || w == "con" {
                if let nw = word(i + 1), nw == "media" || nw == "medio" {
                    total += current.unit / 2
                    i += 2
                    break
                }
                if word(i + 1) == "cuarto", current.unit >= 3600 {
                    total += 900
                    i += 2
                    break
                }
                if let next = term(t, at: i + 1), next.unit < current.unit {
                    total += next.seconds
                    current = next
                    i = next.next
                    continue
                }
                // "1 hora y 20" → 20 minutos (la unidad siguiente).
                if current.unit > 1, let n = SpanishNumber.read(t, at: i + 1), n.value < 60 {
                    total += n.value * current.unit / 60
                    i = n.next
                    break
                }
                break
            }
            // "1 hora 20 minutos"
            if let next = term(t, at: i), next.unit < current.unit {
                total += next.seconds
                current = next
                i = next.next
                continue
            }
            break
        }
        return total > 0 ? (total, i) : nil
    }

    /// Busca la primera duración en el texto (salteando índices ya usados).
    static func find(_ t: [CommandToken], excluding used: Set<Int> = []) -> (seconds: Double, range: Range<Int>)? {
        for i in t.indices where !used.contains(i) {
            if let d = parse(t, at: i), !(i..<d.next).contains(where: { used.contains($0) }) {
                return (d.seconds, i..<d.next)
            }
        }
        return nil
    }
}
