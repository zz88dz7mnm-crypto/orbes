import Foundation

/// Deja lo dicho a ORBEX listo para `CommandParser`: saca muletillas y cortesías, convierte los pedidos
/// educados ("¿me podrías recordar…?") en órdenes ("recordame…") y pasa los números dichos en letras a
/// cifras ("cinco minutos" → "5 minutos").
public enum VoiceCommandCleaner {
    /// Saca muletillas y cortesías ("por favor", "che", "eh", "dale", "bueno", "podrías", "¿me…?") y
    /// normaliza números dichos en letras ("cinco minutos" → "5 minutos") para `CommandParser`.
    public static func clean(_ command: String) -> String {
        let original = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var t = CommandText.tokenize(original)
        guard !t.isEmpty else { return "" }
        var polite = false
        var hadMe = false

        // 1. Muletillas y cortesía del principio.
        var changed = true
        while changed, !t.isEmpty {
            changed = false
            if let n = CommandText.matchPrefix(t, leadingFillers) {
                t.removeFirst(n)
                changed = true
            } else if let n = commaFillerLength(t) {
                t.removeFirst(n)
                changed = true
            } else if let p = politePrefix(t) {
                t.removeFirst(p.count)
                polite = true
                hadMe = hadMe || p.me
                changed = true
            } else if t.count > 1, t[0].norm == "me", meVerbs[t[1].norm] != nil {
                // "¿me ponés…?", "me recordás…": el "me" va pegado al verbo ("poneme", "recordame").
                t.removeFirst()
                polite = true
                hadMe = true
                changed = true
            }
        }

        // 2. El verbo educado pasa a orden ("recordás" → "recordame", "podrías recordar que" → "recordá que").
        if let first = t.first {
            if hadMe, let v = meVerbs[first.norm] {
                t[0] = CommandToken(raw: VoiceText.swapWord(first.raw, v), norm: v)
            } else if polite, let v = plainVerbs[first.norm] {
                t[0] = CommandToken(raw: VoiceText.swapWord(first.raw, v), norm: CommandText.fold(v))
            }
        }

        // 3. Cortesías y titubeos en cualquier lugar ("abrí, por favor, Spotify", "poné eh un timer").
        var i = 0
        while i < t.count {
            if CommandText.hasPrefix(t, ["por", "favor"], at: i) {
                t.removeSubrange(i..<(i + 2))
            } else if anywhereFillers.contains(t[i].norm) {
                t.remove(at: i)
            } else {
                i += 1
            }
        }

        // 4. Cortesías del final.
        changed = true
        while changed, !t.isEmpty {
            changed = false
            for phrase in trailingFillers where CommandText.hasSuffix(t, phrase) {
                t.removeLast(phrase.count)
                changed = true
                break
            }
        }
        guard !t.isEmpty else { return "" }

        // 5. Números en letras → cifras.
        t = numbersToDigits(t)

        // 6. Signos: un pedido educado deja de ser pregunta; una pregunta de verdad conserva su "?".
        var s = t.map(\.raw).joined(separator: " ")
        if polite {
            s = s.trimmingCharacters(in: VoiceText.edgeTrim.union(CharacterSet(charactersIn: "¿?¡!")))
        } else {
            s = s.trimmingCharacters(in: VoiceText.edgeTrim)
            if s.contains("¿"), !s.hasSuffix("?"), original.hasSuffix("?") { s += "?" }
            if s.contains("¡"), !s.hasSuffix("!"), original.hasSuffix("!") { s += "!" }
        }
        return s
    }

    // MARK: - Vocabulario

    static let leadingFillers: [[String]] = [
        ["por", "favor"], ["porfa"], ["porfis"], ["please"], ["che"], ["dale"], ["bueno"], ["buenas"],
        ["hola"], ["ola"], ["oye"], ["hey"], ["ey"], ["ok"], ["okay"], ["okey"], ["listo"], ["vos"],
        ["eh"], ["ehh"], ["ehm"], ["em"], ["emm"], ["mm"], ["mmm"], ["hmm"],
    ]

    /// Muletillas que solo se sacan si van seguidas de coma o puntos suspensivos ("este, abrí…", "a ver…"),
    /// porque también son palabras normales ("este año", "a ver la película").
    static let commaFillers: [[String]] = [["este"], ["mira"], ["escucha"], ["a", "ver"], ["o", "sea"]]

    static let anywhereFillers: Set<String> = [
        "porfa", "porfis", "please", "eh", "ehh", "ehhh", "ehm", "em", "emm", "mm", "mmm", "mmmm", "hmm", "hm", "mhm",
    ]

    static let trailingFillers: [[String]] = [
        ["por", "favor"], ["porfa"], ["porfis"], ["please"], ["muchas", "gracias"], ["gracias"], ["dale"],
        ["che"], ["si", "podes"], ["si", "puedes"], ["si", "podrias"], ["cuando", "puedas"],
    ]

    /// Arranques educados. `me` = el "me" es para el verbo que sigue ("me podrías recordar" → "recordame").
    static let politePhrases: [(words: [String], me: Bool)] = [
        (["me", "podrias"], true), (["me", "podes"], true), (["me", "puedes"], true), (["me", "podras"], true),
        (["me", "podria"], true), (["me", "puede"], true), (["me", "haces", "el", "favor", "de"], true),
        (["me", "harias", "el", "favor", "de"], true), (["me", "hace", "el", "favor", "de"], true),
        (["podrias"], false), (["podes"], false), (["puedes"], false), (["podras"], false), (["podria"], false),
        (["podra"], false), (["puede"], false), (["quiero", "que"], false), (["necesito", "que"], false),
        (["quisiera", "que"], false), (["me", "gustaria", "que"], false), (["haceme", "el", "favor", "de"], false),
        (["hace", "el", "favor", "de"], false), (["harias", "el", "favor", "de"], false),
        (["seria", "posible"], false), (["te", "pido", "que"], false), (["serias", "tan", "amable", "de"], false),
    ]

    /// Verbo después de "me" → orden con "me" ("recordás"/"recordar"/"recuerdes" → "recordame").
    static let meVerbs: [String: String] = {
        let groups: [(String, [String])] = [
            ("recordame", ["recordas", "recuerdas", "recordar", "recuerdes", "recordarias"]),
            ("avisame", ["avisas", "avisar", "avises", "avisarias"]),
            ("anotame", ["anotas", "anotar", "anotes", "anotarias", "apuntas", "apuntar", "apuntes"]),
            ("abrime", ["abris", "abres", "abrir", "abras", "abririas"]),
            ("poneme", ["pones", "poner", "pongas", "pondrias"]),
            ("haceme", ["haces", "hacer", "hagas", "harias"]),
            ("guardame", ["guardas", "guardar", "guardes"]),
            ("creame", ["creas", "crear"]),
            ("escribime", ["escribis", "escribes", "escribir", "escribas"]),
            ("tomame", ["tomas", "tomar", "tomes"]),
            ("dejame", ["dejas", "dejar", "dejes"]),
            ("mostrame", ["mostras", "muestras", "mostrar", "muestres"]),
            ("decime", ["decis", "dices", "decir", "digas"]),
            ("pasame", ["pasas", "pasar", "pases"]),
            ("buscame", ["buscas", "buscar", "busques"]),
            ("lanzame", ["lanzas", "lanzar"]),
            ("iniciame", ["inicias", "iniciar"]),
            ("arrancame", ["arrancas", "arrancar"]),
            ("explicame", ["explicas", "explicar", "expliques"]),
            ("contame", ["contas", "cuentas", "contar", "cuentes"]),
            ("ayudame", ["ayudas", "ayudar", "ayudes"]),
        ]
        var table: [String: String] = [:]
        for (target, forms) in groups { for f in forms { table[f] = target } }
        return table
    }()

    /// Verbo educado sin "me" que `CommandParser` no conoce ("podrías recordar que…" → "recordá que…").
    static let plainVerbs: [String: String] = [
        "recordar": "recordá", "recordas": "recordá", "recuerdas": "recordá", "recuerdes": "recordá",
        "acordarte": "acordate", "acordarse": "acordate",
    ]

    static func politePrefix(_ t: [CommandToken]) -> (count: Int, me: Bool)? {
        politePhrases.filter { CommandText.hasPrefix(t, $0.words) }
            .max { $0.words.count < $1.words.count }
            .map { ($0.words.count, $0.me) }
    }

    static func commaFillerLength(_ t: [CommandToken]) -> Int? {
        for phrase in commaFillers where CommandText.hasPrefix(t, phrase) && t.count > phrase.count {
            let last = t[phrase.count - 1].raw
            if last.hasSuffix(",") || last.hasSuffix("…") || last.hasSuffix("...") { return phrase.count }
        }
        return nil
    }

    // MARK: - Números

    static let unitWords: [String: Int] = [
        "cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "siete": 7, "ocho": 8, "nueve": 9,
    ]
    static let teenWords: [String: Int] = [
        "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16,
        "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiun": 21, "veintiuno": 21,
        "veintiuna": 21, "veintidos": 22, "veintitres": 23, "veinticuatro": 24, "veinticinco": 25,
        "veintiseis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
    ]
    static let tensWords: [String: Int] = [
        "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90,
    ]
    static let hundredWords: [String: Int] = [
        "cien": 100, "ciento": 100, "doscientos": 200, "doscientas": 200, "trescientos": 300, "trescientas": 300,
        "cuatrocientos": 400, "cuatrocientas": 400, "quinientos": 500, "quinientas": 500, "seiscientos": 600,
        "seiscientas": 600, "setecientos": 700, "setecientas": 700, "ochocientos": 800, "ochocientas": 800,
        "novecientos": 900, "novecientas": 900,
    ]

    /// Lee un número en letras desde `t[i]` (0–999). "un"/"una"/"uno" sueltos no cuentan ("poné un timer").
    static func readNumber(_ t: [CommandToken], at i: Int) -> (value: Int, next: Int)? {
        func word(_ k: Int) -> String? { k < t.count ? t[k].norm : nil }
        var value = 0
        var j = i
        var any = false
        if let w = word(j), let h = hundredWords[w] {
            value = h
            j += 1
            any = true
            if w == "cien" { return (value, j) }
        }
        if let w = word(j), let tens = tensWords[w] {
            value += tens
            j += 1
            // "treinta y cinco" (pero "diez y veinte" son dos números: la hora).
            if word(j) == "y", let u = word(j + 1).flatMap({ unitWords[$0] }), u >= 1 {
                value += u
                j += 2
            }
            return (value, j)
        }
        if let w = word(j), let v = teenWords[w] { return (value + v, j + 1) }
        if let w = word(j), let u = unitWords[w], any || u != 1 { return (value + u, j + 1) }
        return any ? (value, j) : nil
    }

    static func numbersToDigits(_ t: [CommandToken]) -> [CommandToken] {
        var out: [CommandToken] = []
        var i = 0
        while i < t.count {
            if let n = readNumber(t, at: i) {
                let first = Array(t[i].raw), last = Array(t[n.next - 1].raw)
                let prefix = String(first.prefix(while: { !$0.isLetter && !$0.isNumber }))
                let suffix = String(last.reversed().prefix(while: { !$0.isLetter && !$0.isNumber }).reversed())
                out.append(CommandToken(raw: prefix + String(n.value) + suffix, norm: String(n.value)))
                i = n.next
            } else {
                out.append(t[i])
                i += 1
            }
        }
        return out
    }
}
