import Foundation

/// Lo que ORBEX entiende sin IA (informe §9.3–9.7).
public enum OrbexCommand: Equatable, Sendable {
    case openApp(name: String)
    case openFolder(path: String)
    case note(text: String)
    /// `seconds <= 0` = sin duración ("poné un timer"): el ejecutor usa los minutos por defecto.
    case timer(seconds: TimeInterval, label: String?)
    case stopwatch
    case pomodoro
    case remind(at: Date, text: String)
    case scheduledAction(at: Date, actionName: String)
    case remember(fact: String)
    case showClock
}

/// Intérprete de pedidos en castellano rioplatense, tolerante a tildes, mayúsculas y relleno
/// ("che", "porfa", "podés"...). Si no entiende, devuelve `nil` (y el pedido va al asistente).
public enum CommandParser {
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> OrbexCommand? {
        parseAll(text, now: now, calendar: calendar).first
    }

    /// Como `parse`, pero devuelve varios comandos cuando el pedido los tiene
    /// ("abrí Figma y la terminal" → dos `openApp`).
    public static func parseAll(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [OrbexCommand] {
        let tokens = CommandText.clean(CommandText.tokenize(text))
        guard !tokens.isEmpty else { return [] }

        if let c = note(tokens) { return [c] }
        if let c = remind(tokens, now: now, calendar: calendar) { return [c] }
        if let c = remember(tokens) { return [c] }
        if let c = scheduledOpen(tokens, now: now, calendar: calendar) { return [c] }
        if let c = keywordCommand(tokens, now: now, calendar: calendar) { return [c] }
        let opened = open(tokens)
        if !opened.isEmpty { return opened }
        if let c = bareDuration(tokens) { return [c] }
        return []
    }

    // MARK: - Vocabulario

    static let noteVerbs: [[String]] = [
        ["anota"], ["anotame"], ["anotar"], ["anotas"], ["anotalo"], ["apunta"], ["apuntame"], ["apuntar"],
        ["nota"], ["toma", "nota"], ["tomame", "nota"], ["tomar", "nota"], ["nueva", "nota"],
        ["guarda", "una", "nota"], ["guardame", "una", "nota"], ["guarda", "nota"], ["guardar", "una", "nota"],
        ["crea", "una", "nota"], ["creame", "una", "nota"], ["crear", "una", "nota"], ["crea", "nota"],
        ["escribi", "una", "nota"], ["escribime", "una", "nota"], ["agrega", "una", "nota"],
        ["hace", "una", "nota"], ["haceme", "una", "nota"], ["dejame", "una", "nota"],
    ]

    static let rememberVerbs: [[String]] = [
        ["acordate"], ["recorda", "que"], ["recorda", "esto"], ["no", "te", "olvides"], ["no", "te", "olvides", "de"],
        ["aprende"], ["aprendete"], ["memoriza"], ["guarda", "en", "tu", "memoria"], ["guarda", "en", "memoria"],
        ["tene", "en", "cuenta"], ["anota", "en", "tu", "memoria"],
    ]

    static let remindVerbs: [[String]] = [
        ["recordame"], ["recordarme"], ["recordamelo"], ["avisame"], ["avisarme"], ["recordas"], ["avisas"],
        ["haceme", "acordar"], ["hacerme", "acordar"], ["recordame", "que"],
    ]

    static let openVerbs: Set<String> = [
        "abri", "abrime", "abrir", "abre", "abras", "abris", "abrirme", "abrilo", "abrila",
        "lanza", "lanzame", "lanzar", "inicia", "iniciame", "iniciar", "arranca", "arrancame", "arrancar",
        "open",
    ]

    static let stopVerbs: Set<String> = [
        "cancela", "cancelar", "cancelame", "frena", "frenar", "frename", "deten", "detene", "detener",
        "borra", "borrar", "elimina", "eliminar", "stop", "apaga", "apagar", "saca", "sacar", "quita", "quitar",
        "termina", "terminar", "pausa", "pausar", "reinicia", "reiniciar", "cerra", "cerrar",
    ]

    static let questionWords: Set<String> = ["cuanto", "cuanta", "cuantos", "que", "como", "donde", "cuando", "cual"]

    static let timerWords: Set<String> = [
        "timer", "timers", "temporizador", "temporizadores", "alarma", "alarmita", "temporiza", "temporizame",
    ]

    static let connectorsStart: Set<String> = ["que", "de", "del", "esto", "lo", "siguiente", "con", "diciendo", "sobre"]
    static let connectorsEnd: Set<String> = ["de", "del", "por", "durante", "en", "y", "a", "para", "que"]

    /// Carpetas conocidas por su nombre en castellano.
    static let folderAliases: [String: String] = [
        "descargas": "~/Downloads", "documentos": "~/Documents", "escritorio": "~/Desktop",
        "imagenes": "~/Pictures", "fotos": "~/Pictures", "musica": "~/Music", "peliculas": "~/Movies",
        "videos": "~/Movies", "aplicaciones": "/Applications", "inicio": "~", "usuario": "~", "home": "~",
        "downloads": "~/Downloads", "documents": "~/Documents", "desktop": "~/Desktop",
    ]
    /// Estas se abren como carpeta aunque no se diga "carpeta" ("abrí descargas").
    static let folderOnlyAliases: Set<String> = ["descargas", "documentos", "escritorio", "downloads", "desktop"]

    // MARK: - Notas

    static func note(_ t: [CommandToken]) -> OrbexCommand? {
        guard let n = CommandText.matchPrefix(t, noteVerbs) else { return nil }
        // "anotá en tu memoria que..." es memoria, no nota.
        if CommandText.hasPrefix(t, ["anota", "en", "tu", "memoria"]) { return nil }
        var rest = Array(t.dropFirst(n))
        rest = CommandText.dropLeading(rest, ["que", "de", "esto", "lo", "siguiente", "con", "diciendo"])
        let text = CommandText.join(rest)
        return text.isEmpty ? nil : .note(text: text)
    }

    // MARK: - Memoria

    static func remember(_ t: [CommandToken]) -> OrbexCommand? {
        guard let n = CommandText.matchPrefix(t, rememberVerbs) else { return nil }
        var rest = Array(t.dropFirst(n))
        rest = CommandText.dropLeading(rest, ["de", "que", "esto", "siempre"])
        let fact = CommandText.join(rest)
        return fact.isEmpty ? nil : .remember(fact: fact)
    }

    // MARK: - Recordatorios

    static func remind(_ t: [CommandToken], now: Date, calendar: Calendar) -> OrbexCommand? {
        var verb: Range<Int>?
        for i in t.indices {
            if let n = CommandText.matchPrefix(t, remindVerbs, at: i) {
                // "recordás"/"avisás" solo con "me" delante ("¿me recordás...?").
                if n == 1, ["recordas", "avisas"].contains(t[i].norm), i == 0 || t[i - 1].norm != "me" { continue }
                verb = i..<(i + n)
                break
            }
        }
        guard let v = verb else { return nil }
        guard let time = TimeExpressionParser.parse(t, excluding: Set(v), now: now, calendar: calendar) else {
            return nil
        }
        let skip = Set(v).union(time.used)
        let fillerBefore: Set<String> = ["acordate", "de", "que", "me", "y", "porfa", "no", "te", "olvides"]
        var words = t.indices.filter { $0 >= v.upperBound && !skip.contains($0) }.map { t[$0] }
        if words.isEmpty {
            words = t.indices.filter { $0 < v.lowerBound && !skip.contains($0) }.map { t[$0] }
            words = CommandText.dropLeading(words, fillerBefore)
            words = CommandText.dropTrailing(words, fillerBefore)
        }
        words = CommandText.dropLeading(words, ["que", "de", "lo", "del", "a"])
        words = CommandText.dropTrailing(words, connectorsEnd)
        let text = CommandText.join(words)
        if text.isEmpty {
            if let rel = time.relativeSeconds { return .timer(seconds: rel, label: nil) }
            return .remind(at: time.date, text: "Recordatorio")
        }
        return .remind(at: time.date, text: text)
    }

    // MARK: - Abrir (ahora o a una hora)

    /// "a las 9 abrime mi setup de trabajo", "abrí Spotify mañana a las 8".
    static func scheduledOpen(_ t: [CommandToken], now: Date, calendar: Calendar) -> OrbexCommand? {
        guard let v = t.firstIndex(where: { openVerbs.contains($0.norm) }) else { return nil }
        guard let time = TimeExpressionParser.parse(t, excluding: [v], now: now, calendar: calendar) else { return nil }
        // Antes del verbo solo puede haber la expresión de tiempo.
        guard (0..<v).allSatisfy({ time.used.contains($0) }) else { return nil }
        var target = t.indices.filter { $0 > v && !time.used.contains($0) }.map { t[$0] }
        target = CommandText.dropLeading(target, CommandText.articles.union(["app", "aplicacion", "programa"]))
        target = CommandText.dropTrailing(target, connectorsEnd)
        let name = CommandText.join(target)
        guard !name.isEmpty else { return nil }
        return .scheduledAction(at: time.date, actionName: name)
    }

    static func open(_ t: [CommandToken]) -> [OrbexCommand] {
        guard let first = t.first, openVerbs.contains(first.norm) else { return [] }
        var target = Array(t.dropFirst())
        target = CommandText.dropLeading(target, CommandText.articles)
        guard let head = target.first else { return [] }

        if ["carpeta", "directorio", "folder"].contains(head.norm) {
            var rest = Array(target.dropFirst())
            rest = CommandText.dropLeading(rest, CommandText.articles.union(["de", "del", "llamada", "que", "se", "llama"]))
            guard !rest.isEmpty else { return [] }
            if rest.count == 1, let alias = folderAliases[rest[0].norm] { return [.openFolder(path: alias)] }
            return [.openFolder(path: CommandText.join(rest))]
        }
        if head.raw.hasPrefix("/") || head.raw.hasPrefix("~") {
            return [.openFolder(path: CommandText.join(target))]
        }
        if target.count == 1, folderOnlyAliases.contains(head.norm), let alias = folderAliases[head.norm] {
            return [.openFolder(path: alias)]
        }

        target = CommandText.dropLeading(target, ["app", "aplicacion", "programa"])
        // Varias apps: "Figma y la terminal", "Slack, Mail e iTerm".
        var groups: [[CommandToken]] = [[]]
        for tok in target {
            if tok.norm == "y" || tok.norm == "e" {
                groups.append([])
                continue
            }
            groups[groups.count - 1].append(tok)
            if tok.raw.hasSuffix(",") { groups.append([]) }
        }
        return groups.compactMap { g -> OrbexCommand? in
            let clean = CommandText.dropLeading(g, CommandText.articles.union(["app", "aplicacion", "programa"]))
            let name = CommandText.join(clean)
            return name.isEmpty ? nil : .openApp(name: AppAliases.canonical(name))
        }
    }

    // MARK: - Reloj, pomodoro, cronómetro, timer

    static func keywordCommand(_ t: [CommandToken], now: Date, calendar: Calendar) -> OrbexCommand? {
        let first = t[0].norm
        let second = t.count > 1 ? t[1].norm : ""
        let isStop = stopVerbs.contains(first) || (first == "para" && CommandText.articles.contains(second))
        if isStop || questionWords.contains(first) { return nil }

        let words = Set(t.map(\.norm))
        let joined = t.map(\.norm).joined(separator: " ")

        if words.contains("reloj") || joined.contains("modo orbit") { return .showClock }
        if words.contains("pomodoro") || words.contains("pomodoros") || joined.contains("modo foco")
            || joined.contains("modo concentracion") {
            return .pomodoro
        }

        let hasTimerWord = !words.isDisjoint(with: timerWords) || joined.contains("cuenta regresiva")
            || joined.contains("cuenta atras")
        let hasStopwatchWord = t.contains { $0.norm.hasPrefix("cronometr") }
        guard hasTimerWord || hasStopwatchWord else { return nil }

        let duration = DurationParser.find(t)
        if hasStopwatchWord && !hasTimerWord && duration == nil { return .stopwatch }

        var used = Set<Int>()
        var seconds: Double = 0
        if let d = duration {
            seconds = d.seconds
            used.formUnion(d.range)
            // "en 5 minutos": el "en" también es parte de la duración.
            if d.range.lowerBound > 0, ["en", "de", "por"].contains(t[d.range.lowerBound - 1].norm) {
                used.insert(d.range.lowerBound - 1)
            }
        } else if hasTimerWord, let time = TimeExpressionParser.parse(t, now: now, calendar: calendar),
                  time.relativeSeconds == nil {
            // "alarma a las 7" → recordatorio.
            let label = timerLabel(t, used: time.used)
            return .remind(at: time.date, text: label ?? "Alarma")
        } else if let i = t.indices.first(where: { SpanishNumber.digits(t[$0].norm) != nil }),
                  let n = SpanishNumber.digits(t[i].norm), n > 0, n <= 600 {
            // "timer de 25": minutos.
            seconds = n * 60
            used.insert(i)
        }
        if hasStopwatchWord && !hasTimerWord && seconds <= 0 { return .stopwatch }
        return .timer(seconds: seconds, label: timerLabel(t, used: used))
    }

    /// Etiqueta del timer: lo que va después de "para" / "llamado" ("para la pizza" → "Pizza").
    static func timerLabel(_ t: [CommandToken], used: Set<Int>) -> String? {
        guard let p = t.indices.first(where: { ["para", "llamado", "llamada", "etiqueta"].contains(t[$0].norm) && !used.contains($0) })
        else { return nil }
        var words = t.indices.filter { $0 > p && !used.contains($0) }.map { t[$0] }
        words = words.filter { !timerWords.contains($0.norm) }
        words = CommandText.dropLeading(words, CommandText.articles.union(["que", "cuando"]))
        words = CommandText.dropTrailing(words, connectorsEnd.union(CommandText.articles))
        let label = CommandText.join(words)
        return label.isEmpty ? nil : CommandText.capitalizedFirst(label)
    }

    /// "5 minutos", "media hora para el té".
    static func bareDuration(_ t: [CommandToken]) -> OrbexCommand? {
        var start = 0
        if ["en", "de", "por"].contains(t[0].norm) { start = 1 }
        guard let d = DurationParser.parse(t, at: start) else { return nil }
        if d.next == t.count { return .timer(seconds: d.seconds, label: nil) }
        if t[d.next].norm == "para" {
            return .timer(seconds: d.seconds, label: timerLabel(t, used: Set(0..<d.next)))
        }
        return nil
    }
}
