import Foundation

/// Qué hacer con lo que se le dijo a ORBEX después de su nombre.
public enum VoiceIntentRouter {
    public enum Route: Equatable, Sendable {
        /// Un comando que ORBEX hace solo (abrir app, timer, nota, recordatorio…).
        case local(OrbexCommand)
        /// Una tarea o pregunta de verdad: va al asistente (Claude), ya limpia.
        case claude(String)
        /// Charla con Orbi (saludos, "¿cómo estás?", "gracias", preguntas cortas sobre Orbi): se contesta
        /// hablando, al toque si es un saludo simple (`VoiceReplies.instant`). Trae lo dicho, sin bordes.
        case chat(String)
        /// "Activá / prendé / abrí el modo inteligente" → `true`; "desactivá / salí del / cerrá / apagá el
        /// modo inteligente" → `false`.
        case smartMode(Bool)
        /// "Cancelá", "nada", "pará", "olvidalo": dejar de escuchar sin hacer nada.
        case stop
        /// No se dijo nada (o solo muletillas).
        case empty
    }

    /// "cancelá"/"nada"/"pará" → .stop; "activá el modo inteligente" → .smartMode; charla ("hola", "¿cómo
    /// estás?", "gracias") → .chat; comando conocido → .local; cualquier otra cosa → .claude(texto limpio).
    /// Si el pedido tiene varios comandos ("abrí Figma y Slack"), `.local` trae el primero; para todos, usar
    /// `CommandParser.parseAll(VoiceCommandCleaner.clean(texto))`.
    public static func route(_ command: String, now: Date = Date(), calendar: Calendar = .current) -> Route {
        let norms = CommandText.tokenize(command).map(\.norm)
        if norms.isEmpty { return .empty }
        if isStop(norms) { return .stop }
        if let on = smartMode(norms) { return .smartMode(on) }
        // Antes de limpiar: el limpiador saca "hola", "bueno", "gracias"… que acá son lo que importa.
        if isSmallTalk(norms) { return .chat(command.trimmingCharacters(in: VoiceText.edgeTrim)) }
        let cleaned = VoiceCommandCleaner.clean(command)
        if cleaned.isEmpty { return .empty }
        if let c = CommandParser.parse(cleaned, now: now, calendar: calendar) { return .local(c) }
        if let c = CommandParser.parse(command, now: now, calendar: calendar) { return .local(c) }
        if isShortChat(CommandText.tokenize(cleaned).map(\.norm)) { return .chat(cleaned) }
        return .claude(cleaned)
    }

    // MARK: - Modo inteligente

    static let smartWords: Set<String> = ["inteligente", "inteligentes", "inteligencia", "smart"]
    static let smartOnWords: Set<String> = [
        "activar", "activa", "activame", "activalo", "activemos", "prende", "prender", "prendeme", "prendelo",
        "abri", "abrir", "abrime", "abre", "encende", "encender", "encendeme", "pone", "poner", "ponete", "ponte",
        "pasa", "pasar", "pasate", "entra", "entrar", "entremos", "inicia", "iniciar", "arranca", "arrancar",
        "mostra", "mostrame", "mostrar", "usa", "usar", "empeza", "empezar", "quiero", "vamos", "on", "enciende",
    ]
    static let smartOffWords: Set<String> = [
        "desactivar", "desactiva", "desactivame", "desactivalo", "sali", "salir", "salite", "salgamos", "sal",
        "cerra", "cerrar", "cerrame", "cerralo", "cierra", "apaga", "apagar", "apagame", "apagalo", "termina",
        "terminar", "quita", "quitar", "quitame", "saca", "sacar", "sacame", "fuera", "chau", "basta", "sin",
        "no", "stop", "frena", "deja", "dejar", "off", "suficiente", "cancela", "cancelar",
    ]
    static let smartFiller: Set<String> = [
        "el", "al", "del", "la", "lo", "en", "de", "a", "un", "ese", "este", "mi", "me", "ahora", "y", "modo",
    ]

    /// "Activá el modo inteligente" → `true`, "salí del modo inteligente" → `false`, otra cosa → `nil`.
    /// Solo si lo dicho es eso (con verbos, artículos y cortesías): "¿qué es el modo inteligente?" no.
    static func smartMode(_ norms: [String]) -> Bool? {
        guard let i = norms.indices.first(where: {
            (norms[$0] == "modo" && $0 + 1 < norms.count && smartWords.contains(norms[$0 + 1]))
                || (norms[$0] == "smart" && $0 + 1 < norms.count && norms[$0 + 1] == "mode")
        }) else { return nil }
        var rest = norms
        rest.removeSubrange(i...(i + 1))
        var off = false
        for w in rest {
            if smartOffWords.contains(w) { off = true; continue }
            if smartOnWords.contains(w) || smartFiller.contains(w) || neutralWords.contains(w) { continue }
            return nil
        }
        return !off
    }

    // MARK: - Charla

    /// Frases de charla con Orbi (normalizadas: sin tildes ni signos).
    static let smallTalkPhrases: [[String]] = [
        ["hola"], ["ola"], ["holis"], ["holaa"], ["buenas"], ["buen", "dia"], ["buenos", "dias"], ["buenas", "tardes"],
        ["buenas", "noches"], ["hey"], ["ey"], ["que", "tal"], ["que", "onda"], ["como", "estas"], ["como", "esta"],
        ["como", "andas"], ["como", "anda"], ["como", "va"], ["como", "te", "va"], ["como", "te", "fue"],
        ["todo", "bien"], ["bien"], ["muy", "bien"], ["re", "bien"], ["mas", "o", "menos"], ["mal"], ["gracias"],
        ["muchas", "gracias"], ["mil", "gracias"], ["genial"], ["joya"], ["barbaro"], ["perfecto"], ["buenisimo"],
        ["excelente"], ["quien", "sos"], ["quien", "eres"], ["que", "sos"], ["como", "te", "llamas"],
        ["como", "te", "llaman"], ["que", "haces"], ["que", "estas", "haciendo"], ["que", "podes", "hacer"],
        ["que", "sabes", "hacer"], ["te", "quiero"], ["sos", "genial"], ["sos", "lo", "mas"], ["jaja"], ["jajaja"],
        ["jajajaja"], ["y", "vos"], ["y", "tu"], ["hasta", "luego"], ["nos", "vemos"], ["hasta", "manana"],
        ["buenas", "buenas"], ["aca", "estoy"], ["aca", "andamos"], ["tirando"],
    ]

    /// ¿Todo lo dicho es charla? ("hola", "hola Orbi, ¿cómo estás?", "bien, ¿y vos?", "gracias").
    static func isSmallTalk(_ norms: [String]) -> Bool {
        var sawTalk = false
        var i = 0
        let words = norms.map { $0.filter { $0.isLetter } }.filter { !$0.isEmpty }
        let tokens = words.map { CommandToken(raw: $0, norm: $0) }
        while i < words.count {
            if let n = CommandText.matchPrefix(tokens, smallTalkPhrases, at: i) {
                sawTalk = true
                i += n
            } else if neutralWords.contains(words[i]) || words[i] == "y" {
                i += 1
            } else {
                return false
            }
        }
        return sawTalk
    }

    /// Palabras que muestran que la pregunta es para Orbi ("¿te gusta la música?", "¿vos dormís?").
    static let secondPerson: Set<String> = [
        "sos", "eres", "estas", "andas", "llamas", "tenes", "tienes", "queres", "quieres", "gusta", "gustan",
        "te", "vos", "tu", "sentis", "sientes", "acordas", "dormis", "comes", "sonas",
    ]

    /// Pregunta corta dirigida a Orbi (hasta 6 palabras, en segunda persona): charla, no tarea.
    static func isShortChat(_ norms: [String]) -> Bool {
        let words = norms.filter { !$0.isEmpty }
        return !words.isEmpty && words.count <= 6 && words.contains(where: secondPerson.contains)
    }

    // MARK: - Cancelar

    /// Palabras que por sí solas cancelan.
    static let stopWords: Set<String> = [
        "cancela", "cancelar", "cancelalo", "cancelo", "cancelado", "cancel", "nada", "no", "para", "pare",
        "basta", "stop", "olvidalo", "olvidate", "olvida", "deja", "dejalo", "chau", "chao", "adios", "callate",
        "calla", "callar", "silencio", "shh", "shhh", "nah", "listo", "perdon", "disculpa", "ninguno", "ninguna",
    ]

    /// Frases que cancelan.
    static let stopPhrases: [[String]] = [
        ["ya", "esta"], ["ya", "fue"], ["no", "importa"], ["me", "equivoque"], ["falsa", "alarma"],
        ["nada", "que", "ver"], ["no", "te", "hablaba"], ["no", "era", "para", "vos"], ["deja", "de", "escuchar"],
        ["no", "escuches"], ["era", "un", "chiste"],
    ]

    /// Palabras que pueden acompañar a una cancelación sin cambiarla ("no, nada, gracias", "pará, che").
    static let neutralWords: Set<String> = {
        var s: Set<String> = [
            "por", "favor", "porfa", "porfis", "please", "eh", "ehh", "em", "emm", "mm", "mmm", "hmm", "che",
            "bueno", "dale", "ok", "okay", "okey", "ya", "mejor", "muchas", "nomas", "vos", "a", "gracias",
        ]
        s.formUnion(WakeWordMatcher.defaultNames.map(VoiceText.key))
        return s
    }()

    /// ¿Todo lo dicho es una cancelación? ("pará el timer" no: eso es un pedido).
    static func isStop(_ norms: [String]) -> Bool {
        var sawStop = false
        var i = 0
        outer: while i < norms.count {
            for phrase in stopPhrases where i + phrase.count <= norms.count && Array(norms[i..<(i + phrase.count)]) == phrase {
                sawStop = true
                i += phrase.count
                continue outer
            }
            if stopWords.contains(norms[i]) {
                sawStop = true
            } else if !neutralWords.contains(norms[i]) {
                return false
            }
            i += 1
        }
        return sawStop
    }
}
