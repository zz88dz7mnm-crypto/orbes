import Foundation

/// Qué hacer con lo que se le dijo a ORBEX después de su nombre.
public enum VoiceIntentRouter {
    public enum Route: Equatable, Sendable {
        /// Un comando que ORBEX hace solo (abrir app, timer, nota, recordatorio…).
        case local(OrbexCommand)
        /// Cualquier otra cosa: va al asistente (Claude), ya limpio.
        case claude(String)
        /// "Cancelá", "nada", "pará", "olvidalo": dejar de escuchar sin hacer nada.
        case stop
        /// No se dijo nada (o solo muletillas).
        case empty
    }

    /// "cancelá"/"nada"/"pará" → .stop; comando conocido → .local; cualquier otra cosa → .claude(texto limpio).
    /// Si el pedido tiene varios comandos ("abrí Figma y Slack"), `.local` trae el primero; para todos, usar
    /// `CommandParser.parseAll(VoiceCommandCleaner.clean(texto))`.
    public static func route(_ command: String, now: Date = Date(), calendar: Calendar = .current) -> Route {
        let norms = CommandText.tokenize(command).map(\.norm)
        if norms.isEmpty { return .empty }
        if isStop(norms) { return .stop }
        let cleaned = VoiceCommandCleaner.clean(command)
        if cleaned.isEmpty { return .empty }
        if let c = CommandParser.parse(cleaned, now: now, calendar: calendar) { return .local(c) }
        if let c = CommandParser.parse(command, now: now, calendar: calendar) { return .local(c) }
        return .claude(cleaned)
    }

    // MARK: - Cancelar

    /// Palabras que por sí solas cancelan.
    static let stopWords: Set<String> = [
        "cancela", "cancelar", "cancelalo", "cancelo", "cancelado", "cancel", "nada", "no", "para", "pare",
        "basta", "stop", "olvidalo", "olvidate", "olvida", "deja", "dejalo", "chau", "chao", "adios", "callate",
        "calla", "silencio", "nah", "gracias", "listo", "perdon", "disculpa", "ninguno", "ninguna",
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
            "bueno", "dale", "ok", "okay", "okey", "ya", "mejor", "muchas", "nomas", "vos", "a",
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
