import Foundation

/// Por qué terminó un pedido dicho en voz alta.
public enum EndReason: Sendable, Equatable {
    /// Hubo habla y después un silencio (`silenceAfterSpeech`).
    case silence
    /// Se llegó al tope de escucha (`maxListen`) aunque se siguiera hablando.
    case maxDuration
    /// No se dijo nada en `noSpeechTimeout`.
    case noSpeech
}

/// Decide cuándo terminó el pedido ("fin de frase") a partir de las transcripciones parciales.
///
/// Uso: `start(at:)` al detectar el nombre; `heard(_:at:)` con cada parcial (idealmente `WakeMatch.command`,
/// así decir solo "Orbex" no cuenta como habla y ORBEX espera el pedido); `isFinished(at:)` en cada tic.
/// Los tiempos son segundos de cualquier reloj monótono (el mismo en todas las llamadas).
/// Una vez vencido el plazo, lo que llegue después se ignora: el resultado y `reason` quedan fijos.
public struct UtteranceEndpointer: Sendable {
    public let silenceAfterSpeech: TimeInterval
    public let maxListen: TimeInterval
    public let noSpeechTimeout: TimeInterval

    public private(set) var startedAt: TimeInterval?
    /// Última vez que la transcripción cambió.
    public private(set) var lastSpeechAt: TimeInterval?
    /// Última transcripción que contó como habla.
    public private(set) var transcript: String = ""
    private var lastKey = ""

    public init(silenceAfterSpeech: TimeInterval = 1.2, maxListen: TimeInterval = 12, noSpeechTimeout: TimeInterval = 5) {
        self.silenceAfterSpeech = silenceAfterSpeech
        self.maxListen = maxListen
        self.noSpeechTimeout = noSpeechTimeout
    }

    public mutating func start(at t: TimeInterval) {
        startedAt = t
        lastSpeechAt = nil
        transcript = ""
        lastKey = ""
    }

    /// Cada transcripción parcial nueva (texto distinto = hubo habla). Cambios de mayúsculas, tildes o
    /// puntuación no cuentan; un texto vacío tampoco.
    public mutating func heard(_ partial: String, at t: TimeInterval) {
        if startedAt == nil { start(at: t) }
        if let end = endTime, t >= end { return }
        let key = VoiceText.speechKey(partial)
        guard !key.isEmpty, key != lastKey else { return }
        lastKey = key
        transcript = partial
        lastSpeechAt = max(t, lastSpeechAt ?? t)
    }

    /// ¿Ya se dijo algo?
    public var hasSpeech: Bool { lastSpeechAt != nil }

    /// ¿Terminó el pedido? (silencio tras hablar, tope total o nada dicho).
    public func isFinished(at t: TimeInterval) -> Bool {
        guard let end = endTime else { return false }
        return t >= end
    }

    /// Por qué terminó el pedido. Vale después de que `isFinished(at:)` dio `true` (antes dice por qué
    /// terminaría si no llega más habla). `nil` si no se llamó a `start(at:)`.
    public var reason: EndReason? { deadline?.reason }

    /// Momento en que termina el pedido si no llega más habla.
    public var endTime: TimeInterval? { deadline?.time }

    var deadline: (time: TimeInterval, reason: EndReason)? {
        guard let s = startedAt else { return nil }
        let maxEnd = s + maxListen
        if let last = lastSpeechAt {
            let silenceEnd = last + silenceAfterSpeech
            return silenceEnd <= maxEnd ? (silenceEnd, .silence) : (maxEnd, .maxDuration)
        }
        return (min(s + noSpeechTimeout, maxEnd), .noSpeech)
    }
}
