import Foundation

/// Momento encontrado en un pedido ("a las 21", "mañana a las 9:30", "en 10 minutos", "el lunes").
struct TimeMatch: Equatable {
    let date: Date
    /// Índices de las palabras que forman la expresión de tiempo.
    let used: Set<Int>
    /// Segundos desde ahora si fue relativa ("en 10 minutos").
    let relativeSeconds: Double?
}

/// Lee expresiones de hora y día en español rioplatense.
enum TimeExpressionParser {
    enum Meridiem { case am, pm }

    static let weekdays: [String: Int] = [
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7,
    ]

    /// "manana/tarde/noche/madrugada" → mañana/tarde y hora por defecto si no se dijo la hora.
    static func meridiemWord(_ w: String) -> (meridiem: Meridiem, defaultHour: Int)? {
        switch w {
        case "manana": return (.am, 9)
        case "madrugada": return (.am, 3)
        case "tarde": return (.pm, 17)
        case "noche": return (.pm, 21)
        default: return nil
        }
    }

    /// Hora en una palabra: "9", "21", "9:30", "9.30", "21hs", "9h30", "21h".
    static func clockToken(_ s: String) -> (hour: Int, minute: Int)? {
        var str = s
        for suf in ["hrs", "hs", "h"] where str.hasSuffix(suf) && str.count > suf.count {
            str.removeLast(suf.count)
            break
        }
        let parts = str.split(separator: ":", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }
            .flatMap { $0.split(separator: "h", omittingEmptySubsequences: false) }
        guard parts.count == 1 || parts.count == 2 else { return nil }
        func isDigits(_ p: Substring) -> Bool { !p.isEmpty && p.allSatisfy { $0.isASCII && $0.isNumber } }
        guard isDigits(parts[0]), parts[0].count <= 2, let h = Int(parts[0]) else { return nil }
        var m = 0
        if parts.count == 2 {
            guard isDigits(parts[1]), parts[1].count == 2, let mm = Int(parts[1]) else { return nil }
            m = mm
        }
        guard (0...24).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Hora después de "a las": "9", "9:30", "nueve", "9 y media", "9 y cuarto", "9 y 20", "10 menos cuarto",
    /// con "hs", "en punto", "am/pm" opcionales.
    static func clock(_ t: [CommandToken], at k: Int) -> (hour: Int, minute: Int, meridiem: Meridiem?, next: Int)? {
        guard k >= 0, k < t.count else { return nil }
        func word(_ i: Int) -> String? { i >= 0 && i < t.count ? t[i].norm : nil }
        var hour: Int
        var minute = 0
        var j = k + 1
        if let c = clockToken(t[k].norm) {
            hour = c.hour
            minute = c.minute
        } else if let n = SpanishNumber.read(t, at: k), n.value == n.value.rounded(), n.value >= 0, n.value <= 24 {
            hour = Int(n.value)
            j = n.next
        } else {
            return nil
        }

        if word(j) == "y" {
            if word(j + 1) == "media" {
                minute = 30
                j += 2
            } else if word(j + 1) == "cuarto" {
                minute = 15
                j += 2
            } else if let n = SpanishNumber.read(t, at: j + 1), n.value == n.value.rounded(), n.value < 60,
                      DurationParser.units[word(n.next) ?? ""] ?? 60 == 60 {
                minute = Int(n.value)
                j = n.next
                if let u = word(j), DurationParser.units[u] == 60 { j += 1 }
            }
        } else if word(j) == "menos" {
            if word(j + 1) == "cuarto" {
                hour -= 1
                minute = 45
                j += 2
            } else if let n = SpanishNumber.read(t, at: j + 1), n.value >= 1, n.value < 60 {
                hour -= 1
                minute = 60 - Int(n.value)
                j = n.next
                if let u = word(j), DurationParser.units[u] == 60 { j += 1 }
            }
            if hour < 0 { hour += 24 }
        }

        var meridiem: Meridiem?
        var moved = true
        while moved {
            moved = false
            if word(j) == "en", word(j + 1) == "punto" { j += 2; moved = true; continue }
            if let w = word(j), ["hs", "h", "hrs", "horas", "hora"].contains(w) { j += 1; moved = true; continue }
            if let w = word(j), ["am", "a.m", "a. m"].contains(w) { meridiem = .am; j += 1; moved = true; continue }
            if let w = word(j), ["pm", "p.m", "p. m"].contains(w) { meridiem = .pm; j += 1; moved = true; continue }
        }
        return (hour, minute, meridiem, j)
    }

    /// Busca día y hora en todo el texto (salteando `excluding`).
    static func parse(_ t: [CommandToken], excluding: Set<Int> = [], now: Date, calendar: Calendar) -> TimeMatch? {
        var used = Set<Int>()
        var relative: Double?
        var dayOffset: Int?
        var weekday: Int?
        var hour: Int?
        var minute = 0
        var meridiem: Meridiem?
        var defaultHour: Int?

        func word(_ k: Int) -> String? {
            guard k >= 0, k < t.count, !excluding.contains(k) else { return nil }
            return t[k].norm
        }
        func mark(_ r: Range<Int>) { used.formUnion(r) }

        var i = 0
        while i < t.count {
            guard let w = word(i) else { i += 1; continue }

            // "en 10 minutos", "dentro de media hora"
            if relative == nil, w == "en" || (w == "dentro" && word(i + 1) == "de") {
                let s = w == "en" ? i + 1 : i + 2
                if let d = DurationParser.parse(t, at: s), !(s..<d.next).contains(where: { excluding.contains($0) }) {
                    relative = d.seconds
                    mark(i..<d.next)
                    i = d.next
                    continue
                }
            }
            if w == "pasado", word(i + 1) == "manana" {
                dayOffset = 2
                mark(i..<(i + 2))
                i += 2
                continue
            }
            if w == "manana", word(i - 1) != "la" {
                dayOffset = 1
                mark(i..<(i + 1))
                i += 1
                continue
            }
            if w == "hoy" {
                dayOffset = 0
                mark(i..<(i + 1))
                i += 1
                continue
            }
            if w == "esta", let n = word(i + 1), let m = meridiemWord(n) {
                dayOffset = 0
                meridiem = m.meridiem
                defaultHour = m.defaultHour
                mark(i..<(i + 2))
                i += 2
                continue
            }
            // "a las 9", "a la una"
            if hour == nil, w == "a", let l = word(i + 1), l == "las" || l == "la",
               let c = clock(t, at: i + 2), !((i + 2)..<c.next).contains(where: { excluding.contains($0) }) {
                hour = c.hour
                minute = c.minute
                if let m = c.meridiem { meridiem = m }
                mark(i..<c.next)
                i = c.next
                continue
            }
            // "de la noche", "por la mañana", "a la tarde"
            if ["de", "por", "a"].contains(w), word(i + 1) == "la", let n = word(i + 2), let m = meridiemWord(n) {
                meridiem = m.meridiem
                if defaultHour == nil { defaultHour = m.defaultHour }
                mark(i..<(i + 3))
                i += 3
                continue
            }
            if w == "del", word(i + 1) == "mediodia" {
                mark(i..<(i + 2))
                i += 2
                continue
            }
            if w == "al", word(i + 1) == "mediodia", hour == nil {
                hour = 12
                minute = 0
                mark(i..<(i + 2))
                i += 2
                continue
            }
            if w == "a", word(i + 1) == "la", word(i + 2) == "medianoche", hour == nil {
                hour = 0
                minute = 0
                mark(i..<(i + 3))
                i += 3
                continue
            }
            if let wd = weekdays[w] {
                weekday = wd
                mark(i..<(i + 1))
                if let p = word(i - 1), ["el", "este", "proximo"].contains(p) { used.insert(i - 1) }
                if word(i - 1) == "proximo", word(i - 2) == "el" { used.insert(i - 2) }
                i += 1
                continue
            }
            // "9:30", "21hs" sueltos (con dos puntos o "hs" para no confundir con cualquier número).
            if hour == nil, w.contains(":") || w.hasSuffix("hs") || (w.contains(".") && w.first?.isNumber == true),
               let c = clock(t, at: i) {
                hour = c.hour
                minute = c.minute
                if let m = c.meridiem { meridiem = m }
                mark(i..<c.next)
                i = c.next
                continue
            }
            i += 1
        }

        if hour == nil, dayOffset == nil, weekday == nil, relative == nil, defaultHour == nil { return nil }

        if let rel = relative, hour == nil, dayOffset == nil, weekday == nil {
            return TimeMatch(date: now.addingTimeInterval(rel), used: used, relativeSeconds: rel)
        }

        var h = hour ?? defaultHour ?? 9
        let m = hour == nil ? 0 : minute
        if let mer = meridiem {
            if mer == .pm && h < 12 { h += 12 }
            if mer == .am && h == 12 { h = 0 }
        }
        if h == 24 { h = 0 }

        let today = calendar.startOfDay(for: now)
        var baseDay = today
        if let off = dayOffset {
            baseDay = calendar.date(byAdding: .day, value: off, to: today) ?? today
        } else if let wd = weekday {
            let current = calendar.component(.weekday, from: now)
            let diff = (wd - current + 7) % 7
            baseDay = calendar.date(byAdding: .day, value: diff, to: today) ?? today
        }
        guard var date = calendar.date(bySettingHour: h, minute: m, second: 0, of: baseDay) else { return nil }
        if date <= now {
            if dayOffset == nil && weekday == nil {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            } else if dayOffset == nil, weekday != nil {
                date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
            }
        }
        return TimeMatch(date: date, used: used, relativeSeconds: nil)
    }
}
