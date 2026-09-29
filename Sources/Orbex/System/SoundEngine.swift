import AVFoundation
import OrbexCore

/// Sonidos de ORBEX (informe §8). No hay archivos: todo se sintetiza por código (osciladores + envolventes)
/// con notas de la pentatónica de Do mayor (Do, Re, Mi, Sol, La; octavas 4 a 7), así nunca desafinan entre sí.
/// Cada tema tiene su timbre: Liquid Glass = campanitas/gotas de vidrio, macOS limpio = senoidal suave con
/// clic, Y2K = chiptune de onda cuadrada.
///
/// El motor arranca recién con el primer sonido y se pausa solo después de un rato sin sonar
/// (casi 0 % de CPU en reposo). Si el audio falla, ORBEX se queda callado; nunca se cae.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    private struct CacheKey: Hashable {
        let theme: ThemeID
        let sound: SoundID
    }

    private static let sampleRate: Double = 44_100
    private static let poolSize = 6
    private static let idlePauseSeconds: Double = 12
    /// Bajada de volumen mientras suena música.
    private static let duckFactor = 0.45
    /// Volumen por defecto de la isla (escala 0–0,2 de la base); el ajuste se aplica relativo a este valor.
    private static let islandDefaultVolume = 0.12
    /// Separación mínima entre dos disparos del mismo sonido (anti-ráfaga).
    private static let burstGap: TimeInterval = 0.035

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isSetUp = false
    private var retryAfter: TimeInterval = 0
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SoundID: TimeInterval] = [:]
    private var idleWork: DispatchWorkItem?
    private var configObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Nombres de eventos de la isla (base Coucou)

    /// Silencio general de la isla (además del ajuste "Sonido" de `AppState`).
    var enabled = true
    /// Volumen de la isla en la escala de la base (0–0,2). Se usa como multiplicador relativo a 0,12
    /// sobre el volumen de ORBEX (0,12 = sin cambio, 0 = mudo, 0,2 ≈ +67 %).
    var volume: Float = 0.12

    /// Reproduce un evento de la isla por nombre ("peek", "open", "slap", "gulp"…). Cada uno de los
    /// 28 nombres tiene su propio sonido sintetizado de ORBEX (nunca se usan los WAV de Coucou).
    /// Nombres desconocidos no suenan.
    func play(_ name: String) {
        guard enabled, AppState.shared.soundEnabled, let event = IslandSound(rawValue: name) else { return }
        let settings = AppModel.shared.settings
        // Los silencios por evento de Configuración se aplican por grupo (el `OrbexSound` equivalente).
        if let group = Self.eventSounds[name], settings.mutedSounds.contains(group.rawValue) { return }
        let relative = min(2, max(0, AppState.shared.soundVolume / Self.islandDefaultVolume))
        guard relative > 0.001 else { return }
        play(.island(event), extraGain: relative)
    }

    /// Nombre de evento de la isla → sonido de ORBEX del mismo grupo. Ya no decide el timbre (cada evento
    /// tiene el suyo en `IslandSound`); sirve para los silencios por evento y el anti-ráfaga de `BotSoundGate`.
    static let eventSounds: [String: OrbexSound] = [
        "peek": .peek, "open": .open, "close": .close, "hover": .rareBlink, "blip": .tap,
        "slap": .tap, "annoyed": .annoyed, "dizzy": .dizzy, "greet": .greet, "work": .timerStart,
        "finish": .sessionDone, "error": .error, "approval": .needsYou, "question": .surprise,
        "approve": .permissionGranted, "gulp": .fileSwallowed, "tick": .tick, "send": .answered,
        "love": .wake, "pop": .lap, "proud": .sessionDone, "wink": .rareBlink, "yawn": .sleep,
        "attach": .noteSaved, "think": .thinking, "search": .thinking, "rate": .permissionDenied,
        "sleep": .sleep,
    ]

    // MARK: - API

    /// Reproduce un sonido respetando volumen, horario silencioso, silencios por evento y ducking.
    func play(_ s: OrbexSound) {
        guard !AppModel.shared.settings.mutedSounds.contains(s.rawValue) else { return }
        play(.orbex(s), extraGain: 1)
    }

    /// Vista previa desde Configuración: suena aunque el evento esté silenciado o sea horario silencioso.
    func preview(_ s: OrbexSound, theme: ThemeID) {
        let volume = min(1, max(0, AppModel.shared.settings.volume)) * SoundSynth.gain(for: .orbex(s))
        guard volume > 0.001 else { return }
        schedule(.orbex(s), theme: theme, volume: volume)
    }

    /// Prepara los buffers de un tema (sin tocar el hardware de audio) para que el primer sonido salga al toque.
    func preload(theme: ThemeID? = nil) {
        let t = theme ?? AppModel.shared.settings.theme
        for s in OrbexSound.allCases {
            _ = buffer(for: .orbex(s), theme: t)
        }
        for e in IslandSound.allCases {
            _ = buffer(for: .island(e), theme: t)
        }
    }

    /// Camino común: volumen de ORBEX (horario silencioso incluido), ducking, ganancia del evento y anti-ráfaga.
    private func play(_ id: SoundID, extraGain: Double) {
        let model = AppModel.shared
        let settings = model.settings
        let hour = Calendar.current.component(.hour, from: Date())
        var volume = settings.effectiveVolume(hour: hour)
        if model.isPlayingMusic && settings.duckWithMusic { volume *= Self.duckFactor }
        volume *= SoundSynth.gain(for: id) * extraGain
        guard volume > 0.001 else { return }

        // Evitar ráfagas del mismo sonido (p. ej. muchos "tic" en el mismo instante).
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[id], now - last < Self.burstGap { return }
        lastPlayed[id] = now

        schedule(id, theme: settings.theme, volume: volume)
    }

    // MARK: - Reproducción

    private func schedule(_ s: SoundID, theme: ThemeID, volume: Double) {
        guard let buffer = buffer(for: s, theme: theme), startIfNeeded(), !players.isEmpty else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float(min(1, max(0, volume)))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
        scheduleIdlePause()
    }

    private func setUpIfNeeded() -> Bool {
        if isSetUp { return true }
        guard let format else { return false }
        let mixer = engine.mainMixerNode
        for _ in 0..<Self.poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players.append(player)
        }
        // Cambió la salida de audio (auriculares, parlantes, AirPods…): macOS para el motor.
        // Los nodos siguen conectados; se vuelve a arrancar solo con el próximo sonido.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
        engine.prepare()
        isSetUp = true
        return true
    }

    private func startIfNeeded() -> Bool {
        guard setUpIfNeeded() else { return false }
        if engine.isRunning { return true }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= retryAfter else { return false }
        do {
            try engine.start()
            return true
        } catch {
            NSLog("ORBEX: no se pudo iniciar el audio: %@", error.localizedDescription)
            retryAfter = now + 5
            return false
        }
    }

    private func configurationChanged() {
        idleWork?.cancel()
        idleWork = nil
        retryAfter = 0
        if isSetUp && !engine.isRunning {
            engine.prepare()
        }
    }

    /// Pausa el motor después de un rato sin sonidos (ahorra CPU y batería).
    private func scheduleIdlePause() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.pauseIfIdle() }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idlePauseSeconds, execute: work)
    }

    private func pauseIfIdle() {
        idleWork = nil
        guard engine.isRunning else { return }
        for player in players { player.stop() }
        engine.pause()
    }

    private func buffer(for s: SoundID, theme: ThemeID) -> AVAudioPCMBuffer? {
        let key = CacheKey(theme: theme, sound: s)
        if let cached = cache[key] { return cached }
        guard let format else { return nil }
        let samples = SoundSynth.render(s, voice: SoundSynth.Voice(theme), sampleRate: Self.sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count {
            channel[i] = samples[i]
        }
        cache[key] = buffer
        return buffer
    }
}

// MARK: - Síntesis (Swift puro, sin AVFoundation)

/// Los 28 eventos que la isla (base Coucou) pide por nombre. Cada uno tiene su sonido sintetizado propio,
/// original de ORBEX; el `rawValue` es el nombre que usa la isla.
enum IslandSound: String, CaseIterable {
    case peek, open, close, hover, blip, slap, annoyed, dizzy, greet, work, finish, error, approval
    case question, approve, gulp, tick, send, love, pop, proud, wink, yawn, attach, think, search
    case rate, sleep
}

/// Identidad de un sonido en el motor: un evento de ORBEX o un evento de la isla.
enum SoundID: Hashable {
    case orbex(OrbexSound)
    case island(IslandSound)
}

/// Una nota: frecuencia (Hz), inicio y duración (s), amplitud relativa, glissando opcional hasta otra nota,
/// soplo de ruido (0–1, para golpecitos y "fsss") y vibrato (profundidad en fracción de la frecuencia).
struct SynthNote {
    var freq: Double
    var start: Double
    var dur: Double
    var amp: Double
    var glideTo: Double?
    var noise: Double = 0
    var vibrato: Double = 0
}

/// Arma y renderiza los sonidos. Todas las notas salen de la pentatónica de Do mayor (octavas 4–7);
/// los glissandos empiezan y terminan en notas de la escala.
enum SoundSynth {
    /// Timbre según el tema.
    enum Voice {
        /// Liquid Glass: senoidal + parcial inarmónico ×2,76 que se apaga rápido (campanita de vidrio).
        case glass
        /// macOS limpio: senoidal suave con un clic cortito al principio.
        case soft
        /// Y2K: onda cuadrada de 8 bits con volumen "escalonado".
        case chip

        init(_ theme: ThemeID) {
            switch theme {
            case .liquidGlass: self = .glass
            case .macClean: self = .soft
            case .y2k: self = .chip
            }
        }

        var attack: Double {
            switch self {
            case .glass: return 0.002
            case .soft: return 0.006
            case .chip: return 0.001
            }
        }

        /// Constante de caída exponencial, en fracción de la duración de la nota.
        var decay: Double {
            switch self {
            case .glass: return 0.38
            case .soft: return 0.30
            case .chip: return 1.5
            }
        }

        /// Pico final (la cuadrada suena más fuerte a igual amplitud).
        var peak: Double {
            switch self {
            case .glass: return 0.85
            case .soft: return 0.80
            case .chip: return 0.45
            }
        }
    }

    /// Pentatónica de Do mayor (Hz).
    enum P {
        static let C4 = 261.63, D4 = 293.66, E4 = 329.63, G4 = 392.00, A4 = 440.00
        static let C5 = 523.25, D5 = 587.33, E5 = 659.26, G5 = 783.99, A5 = 880.00
        static let C6 = 1046.50, D6 = 1174.66, E6 = 1318.51, G6 = 1567.98, A6 = 1760.00
        static let C7 = 2093.00, D7 = 2349.32, E7 = 2637.02, G7 = 3135.96, A7 = 3520.00
    }

    private static func n(_ freq: Double, _ start: Double, _ dur: Double, _ amp: Double = 0.6,
                          glide: Double? = nil, noise: Double = 0, vib: Double = 0) -> SynthNote {
        SynthNote(freq: freq, start: start, dur: dur, amp: amp, glideTo: glide, noise: noise, vibrato: vib)
    }

    /// Volumen relativo de cada sonido (los frecuentes, más bajitos).
    static func gain(for id: SoundID) -> Double {
        switch id {
        case .orbex(let s): return orbexGain(s)
        case .island(let e): return islandGain(e)
        }
    }

    /// Volumen relativo de cada evento (los frecuentes, más bajitos).
    private static func orbexGain(_ s: OrbexSound) -> Double {
        switch s {
        case .tick: return 0.35
        case .rareBlink: return 0.4
        case .thinking: return 0.45
        case .peek, .lap: return 0.55
        case .tap, .open, .close, .dizzy, .annoyed, .assistantMessage: return 0.65
        case .sleep, .wake, .noteSaved, .timerStart, .newSong, .toClock, .toNotch, .surprise, .fileSwallowed:
            return 0.7
        case .greet, .answered, .permissionGranted, .permissionDenied, .sessionDone: return 0.8
        case .error: return 0.85
        case .needsYou: return 0.9
        case .timerDone: return 0.95
        case .alarm: return 1.0
        }
    }

    /// Volumen relativo de los eventos de la isla: los de roce (hover, tick, blip) casi susurrados.
    private static func islandGain(_ e: IslandSound) -> Double {
        switch e {
        case .tick: return 0.18
        case .hover: return 0.22
        case .blip: return 0.3
        case .think, .search, .wink: return 0.35
        case .pop, .peek: return 0.45
        case .yawn, .sleep, .close: return 0.5
        case .open, .attach, .send, .work, .dizzy: return 0.55
        case .slap, .annoyed, .question, .love, .rate: return 0.6
        case .gulp, .greet: return 0.65
        case .approve, .proud: return 0.72
        case .finish, .error: return 0.8
        case .approval: return 0.88
        }
    }

    /// Partitura de un sonido, con la variante del tema aplicada.
    static func notes(for id: SoundID, voice: Voice) -> [SynthNote] {
        switch id {
        case .orbex(let s): return orbexNotes(s)
        case .island(let e): return variant(islandNotes(e), voice: voice)
        }
    }

    /// Partitura de cada sonido de ORBEX (0,05–0,9 s).
    static func orbexNotes(_ s: OrbexSound) -> [SynthNote] {
        switch s {
        case .greet: // arpegio que sube
            return [n(P.C5, 0, 0.30), n(P.E5, 0.07, 0.30), n(P.G5, 0.14, 0.30, 0.65),
                    n(P.C6, 0.21, 0.42, 0.7), n(P.E6, 0.30, 0.34, 0.35)]
        case .peek: // gotita suave
            return [n(P.E5, 0, 0.16, 0.5, glide: P.A5)]
        case .open: // sube
            return [n(P.E5, 0, 0.12, 0.5), n(P.A5, 0.06, 0.22)]
        case .close: // baja
            return [n(P.A5, 0, 0.12, 0.5), n(P.E5, 0.06, 0.22, 0.55)]
        case .tap: // blip
            return [n(P.C6, 0, 0.08)]
        case .annoyed: // gruñidito grave
            return [n(P.E4, 0, 0.12, 0.6, glide: P.D4), n(P.D4, 0.12, 0.20, 0.6, glide: P.C4)]
        case .dizzy: // tambaleo
            return [n(P.G5, 0, 0.13, 0.5, glide: P.E5), n(P.E5, 0.13, 0.13, 0.5, glide: P.G5),
                    n(P.G5, 0.26, 0.13, 0.45, glide: P.D5), n(P.D5, 0.39, 0.22, 0.4, glide: P.C5)]
        case .rareBlink: // chiquitito
            return [n(P.A6, 0, 0.06, 0.4)]
        case .sleep: // baja lento
            return [n(P.G5, 0, 0.30, 0.5), n(P.E5, 0.15, 0.30, 0.45),
                    n(P.D5, 0.30, 0.30, 0.4), n(P.C5, 0.45, 0.42, 0.35)]
        case .wake: // sube
            return [n(P.C5, 0, 0.18, 0.5), n(P.D5, 0.07, 0.18, 0.5),
                    n(P.E5, 0.14, 0.18, 0.55), n(P.G5, 0.21, 0.30)]
        case .needsYou: // doble ping
            return [n(P.A5, 0, 0.20, 0.7), n(P.A5, 0.18, 0.34, 0.7), n(P.E6, 0.18, 0.34, 0.2)]
        case .permissionGranted:
            return [n(P.G5, 0, 0.12, 0.55), n(P.C6, 0.07, 0.14, 0.55), n(P.G6, 0.14, 0.32, 0.55)]
        case .permissionDenied:
            return [n(P.D5, 0, 0.14, 0.55), n(P.A4, 0.11, 0.30, 0.55)]
        case .answered:
            return [n(P.G5, 0, 0.14, 0.55), n(P.E6, 0.09, 0.32, 0.55)]
        case .sessionDone: // corridita feliz
            return [n(P.C5, 0, 0.14, 0.5), n(P.D5, 0.05, 0.14, 0.5), n(P.E5, 0.10, 0.14, 0.55),
                    n(P.G5, 0.15, 0.14, 0.55), n(P.A5, 0.20, 0.14, 0.6),
                    n(P.C6, 0.25, 0.40, 0.7), n(P.E6, 0.25, 0.40, 0.3)]
        case .error: // par grave
            return [n(P.D4, 0, 0.16, 0.65), n(P.C4, 0.18, 0.30, 0.65)]
        case .assistantMessage: // burbuja
            return [n(P.A5, 0, 0.10, 0.45, glide: P.C6), n(P.E6, 0.08, 0.24, 0.45)]
        case .thinking: // trino
            return (0..<8).map { i in
                n(i % 2 == 0 ? P.D6 : P.E6, Double(i) * 0.05, 0.05, 0.3)
            }
        case .fileSwallowed: // trago: glissando hacia abajo
            return [n(P.C6, 0, 0.28, 0.6, glide: P.C5), n(P.G4, 0.25, 0.14, 0.45)]
        case .timerStart:
            return [n(P.G5, 0, 0.09, 0.5), n(P.D6, 0.07, 0.24, 0.55)]
        case .tick: // clic
            return [n(P.E7, 0, 0.045, 0.5)]
        case .timerDone:
            return [n(P.C6, 0, 0.20, 0.65), n(P.E6, 0.12, 0.20, 0.65),
                    n(P.G6, 0.24, 0.22, 0.65), n(P.C7, 0.36, 0.44, 0.7)]
        case .alarm:
            return [n(P.A6, 0, 0.12, 0.8), n(P.E6, 0.13, 0.12, 0.8), n(P.A6, 0.26, 0.12, 0.8),
                    n(P.E6, 0.39, 0.12, 0.8), n(P.A6, 0.52, 0.30, 0.8)]
        case .lap:
            return [n(P.E6, 0, 0.07, 0.5), n(P.A6, 0.06, 0.14, 0.5)]
        case .noteSaved:
            return [n(P.C6, 0, 0.08, 0.45), n(P.E6, 0.05, 0.08, 0.45), n(P.A6, 0.10, 0.26, 0.5)]
        case .newSong:
            return [n(P.C5, 0, 0.30, 0.4), n(P.G5, 0.10, 0.30, 0.4), n(P.E6, 0.20, 0.40, 0.45)]
        case .toClock: // glissando hacia arriba
            return [n(P.C5, 0, 0.45, 0.55, glide: P.C6), n(P.G6, 0.36, 0.30, 0.3)]
        case .toNotch: // glissando hacia abajo
            return [n(P.C6, 0, 0.45, 0.55, glide: P.C5), n(P.G4, 0.36, 0.26, 0.3)]
        case .surprise: // chispitas
            return [n(P.A6, 0, 0.16, 0.4), n(P.C7, 0.04, 0.16, 0.38), n(P.E7, 0.08, 0.16, 0.34),
                    n(P.G7, 0.12, 0.16, 0.3), n(P.A7, 0.16, 0.26, 0.28)]
        }
    }

    /// Partitura de cada evento de la isla (0,03–0,8 s). Todo original de ORBEX, en la pentatónica.
    static func islandNotes(_ e: IslandSound) -> [SynthNote] {
        switch e {
        case .peek: // se asoma: gotita que sube y un brillito
            return [n(P.G5, 0, 0.11, 0.5, glide: P.C6), n(P.A6, 0.07, 0.10, 0.18)]
        case .open: // se abre: tres escalones rápidos que florecen
            return [n(P.E5, 0, 0.08, 0.42), n(P.G5, 0.035, 0.08, 0.46),
                    n(P.C6, 0.07, 0.24, 0.55), n(P.G6, 0.07, 0.20, 0.12)]
        case .close: // se cierra: pliegue hacia abajo que se apaga
            return [n(P.C6, 0, 0.07, 0.45), n(P.G5, 0.035, 0.07, 0.42),
                    n(P.D5, 0.07, 0.20, 0.45, glide: P.C5)]
        case .hover: // roce: una pizca aguda
            return [n(P.D7, 0, 0.035, 0.35)]
        case .blip: // toque: punto redondo
            return [n(P.A6, 0, 0.05, 0.45, glide: P.C7)]
        case .slap: // palmadita: golpe de aire con cuerpo grave
            return [n(P.G4, 0, 0.11, 0.6, glide: P.C4, noise: 0.55), n(P.D5, 0.01, 0.05, 0.25, noise: 0.3)]
        case .annoyed: // "mmf": dos notas graves con temblor
            return [n(P.E4, 0, 0.09, 0.55, vib: 0.02), n(P.D4, 0.10, 0.22, 0.6, glide: P.C4, vib: 0.03)]
        case .dizzy: // mareo: espiral que ondula y cae
            return [n(P.A5, 0, 0.16, 0.45, glide: P.E5, vib: 0.04), n(P.G5, 0.14, 0.16, 0.42, glide: P.D5, vib: 0.05),
                    n(P.E5, 0.28, 0.16, 0.4, glide: P.C5, vib: 0.06), n(P.D5, 0.42, 0.26, 0.35, glide: P.A4, vib: 0.06)]
        case .greet: // "¡hola!": salto de quinta y acorde abierto
            return [n(P.D5, 0, 0.12, 0.5), n(P.A5, 0.08, 0.14, 0.55),
                    n(P.D6, 0.18, 0.40, 0.55), n(P.A6, 0.18, 0.36, 0.2), n(P.E6, 0.24, 0.34, 0.25)]
        case .work: // manos a la obra: pulso doble decidido
            return [n(P.C5, 0, 0.07, 0.5), n(P.G5, 0.06, 0.07, 0.5), n(P.C5, 0.14, 0.07, 0.45),
                    n(P.A5, 0.20, 0.20, 0.5)]
        case .finish: // listo: corrida y acorde de Do
            return [n(P.G5, 0, 0.08, 0.45), n(P.A5, 0.04, 0.08, 0.45), n(P.C6, 0.08, 0.08, 0.5),
                    n(P.D6, 0.12, 0.08, 0.5), n(P.E6, 0.16, 0.10, 0.55),
                    n(P.C6, 0.22, 0.50, 0.5), n(P.E6, 0.22, 0.50, 0.35), n(P.G6, 0.22, 0.50, 0.3)]
        case .error: // algo falló: caída con tropiezo
            return [n(P.A4, 0, 0.14, 0.6, glide: P.E4), n(P.D4, 0.16, 0.10, 0.55), n(P.C4, 0.26, 0.28, 0.6)]
        case .approval: // te necesito: timbre de dos tonos, dos veces
            return [n(P.E6, 0, 0.14, 0.65), n(P.C6, 0.12, 0.22, 0.6),
                    n(P.E6, 0.40, 0.14, 0.65), n(P.C6, 0.52, 0.28, 0.6), n(P.G6, 0.52, 0.28, 0.15)]
        case .question: // "¿mm?": inflexión que sube
            return [n(P.D5, 0, 0.12, 0.45), n(P.E5, 0.10, 0.20, 0.5, glide: P.A5), n(P.D6, 0.28, 0.08, 0.25)]
        case .approve: // aprobado: dos notas brillantes y chispa
            return [n(P.C6, 0, 0.10, 0.55), n(P.G6, 0.07, 0.30, 0.55), n(P.C7, 0.12, 0.22, 0.18)]
        case .gulp: // trago: garganta que baja y burbujita
            return [n(P.A5, 0, 0.14, 0.55, glide: P.C5), n(P.D4, 0.13, 0.08, 0.45, noise: 0.15),
                    n(P.E5, 0.24, 0.06, 0.3, glide: P.A5)]
        case .tick: // tic de reloj
            return [n(P.G7, 0, 0.03, 0.4, noise: 0.2)]
        case .send: // enviado: soplido que despega
            return [n(P.C5, 0, 0.18, 0.4, glide: P.C7, noise: 0.25), n(P.G6, 0.16, 0.14, 0.3)]
        case .love: // cariño: dos notas tibias con vibrato
            return [n(P.E5, 0, 0.18, 0.5, vib: 0.012), n(P.G5, 0.14, 0.18, 0.5, vib: 0.012),
                    n(P.C6, 0.28, 0.44, 0.55, vib: 0.015), n(P.E6, 0.28, 0.40, 0.18)]
        case .pop: // pop de burbuja
            return [n(P.D5, 0, 0.06, 0.5, glide: P.D6)]
        case .proud: // orgullo: corto-corto-largo
            return [n(P.G5, 0, 0.07, 0.5), n(P.G5, 0.09, 0.07, 0.5),
                    n(P.C6, 0.18, 0.40, 0.6), n(P.E6, 0.18, 0.40, 0.3), n(P.G6, 0.26, 0.30, 0.15)]
        case .wink: // guiño: rebote agudo
            return [n(P.A6, 0, 0.05, 0.4), n(P.E7, 0.05, 0.08, 0.3)]
        case .yawn: // bostezo: sube un poco y se estira hacia abajo
            return [n(P.C5, 0, 0.18, 0.4, glide: P.G5, vib: 0.01),
                    n(P.G5, 0.18, 0.50, 0.45, glide: P.C5, vib: 0.02)]
        case .attach: // adjuntar: clic y encaje
            return [n(P.E6, 0, 0.03, 0.4, noise: 0.35), n(P.C6, 0.04, 0.08, 0.45), n(P.G6, 0.10, 0.18, 0.45)]
        case .think: // pensando: vaivén lento y bajito
            return [n(P.A5, 0, 0.12, 0.35), n(P.C6, 0.13, 0.12, 0.32),
                    n(P.A5, 0.26, 0.12, 0.3), n(P.D6, 0.39, 0.18, 0.3)]
        case .search: // buscando: barrido de radar
            return [n(P.E6, 0, 0.07, 0.3), n(P.G6, 0.06, 0.07, 0.3), n(P.A6, 0.12, 0.07, 0.3),
                    n(P.G6, 0.18, 0.07, 0.28), n(P.E6, 0.24, 0.14, 0.26)]
        case .rate: // puntuar: estrellitas que suben
            return [n(P.C6, 0, 0.08, 0.4), n(P.E6, 0.05, 0.08, 0.4), n(P.G6, 0.10, 0.08, 0.4),
                    n(P.A6, 0.15, 0.08, 0.4), n(P.C7, 0.20, 0.24, 0.45)]
        case .sleep: // a dormir: cuatro notas que bajan y se apagan
            return [n(P.E5, 0, 0.28, 0.45, vib: 0.008), n(P.D5, 0.18, 0.28, 0.4, vib: 0.008),
                    n(P.C5, 0.36, 0.28, 0.35, vib: 0.01), n(P.A4, 0.54, 0.40, 0.3, vib: 0.012)]
        }
    }

    /// Variante por tema de las partituras de la isla (además del timbre de `Voice`):
    /// vidrio = suma un eco una octava arriba en la última nota; macOS limpio = colas más cortas y sin
    /// soplo de ruido; chiptune = sin vibrato (se pierde en la cuadrada) y ruido más marcado.
    static func variant(_ notes: [SynthNote], voice: Voice) -> [SynthNote] {
        switch voice {
        case .glass:
            guard let last = notes.max(by: { $0.start + $0.dur < $1.start + $1.dur }),
                  last.freq * 2 <= P.A7 + 1, last.dur >= 0.1 else { return notes }
            var echo = last
            echo.freq *= 2
            echo.glideTo = echo.glideTo.map { $0 * 2 }
            echo.start += 0.03
            echo.amp *= 0.18
            echo.noise = 0
            echo.vibrato = 0
            return notes + [echo]
        case .soft:
            return notes.map { note in
                var m = note
                m.dur *= 0.85
                m.noise *= 0.4
                return m
            }
        case .chip:
            return notes.map { note in
                var m = note
                m.vibrato = 0
                m.noise = Swift.min(1, m.noise * 1.3)
                return m
            }
        }
    }

    /// Renderiza un sonido a muestras mono (float, −1…1).
    static func render(_ id: SoundID, voice: Voice, sampleRate: Double) -> [Float] {
        let list = notes(for: id, voice: voice)
        let total = list.map { $0.start + $0.dur }.max() ?? 0
        guard total > 0, sampleRate > 0 else { return [] }
        var out = [Double](repeating: 0, count: max(1, Int((total + 0.005) * sampleRate)))
        for (i, note) in list.enumerated() {
            add(note, voice: voice, seed: UInt32(truncatingIfNeeded: i &* 2_654_435_761 &+ 1),
                sampleRate: sampleRate, into: &out)
        }
        let peak = out.reduce(0) { Swift.max($0, abs($1)) }
        guard peak > 0 else { return [] }
        let gain = voice.peak / peak
        return out.map { Float($0 * gain) }
    }

    private static func add(_ note: SynthNote, voice: Voice, seed: UInt32, sampleRate sr: Double,
                            into out: inout [Double]) {
        let startIndex = Int(note.start * sr)
        let count = Int(note.dur * sr)
        guard count > 0, note.freq > 0, startIndex >= 0, startIndex < out.count else { return }
        let twoPi = 2 * Double.pi
        let attack = voice.attack
        let tau = Swift.max(0.01, note.dur * voice.decay)
        let release = Swift.min(0.012, note.dur * 0.3)
        let ratio = note.glideTo.map { $0 / note.freq }
        var phase = 0.0
        var partialPhase = 0.0
        // Ruido determinístico (mismo buffer siempre, apto para caché). En chiptune se sostiene unas
        // muestras para sonar "a 8 bits".
        var rng = seed == 0 ? 0x9E37_79B9 : seed
        var held = 0.0
        var lowpassed = 0.0

        for i in 0..<count {
            let index = startIndex + i
            if index >= out.count { break }
            let t = Double(i) / sr
            var freq = note.freq
            if let ratio {
                let x = t / note.dur
                if case .chip = voice {
                    // Glissando en escalones (como un arpegiador de consola).
                    freq = note.freq * pow(ratio, (x * 8).rounded(.down) / 8)
                } else {
                    freq = note.freq * pow(ratio, x)
                }
            }
            if note.vibrato > 0 {
                freq *= 1 + note.vibrato * sin(twoPi * 5.5 * t) * Swift.min(1, t / 0.08)
            }

            // Envolvente: ataque lineal, caída exponencial y un soltado cortito para que no haga "clic".
            var env = t < attack ? t / attack : exp(-(t - attack) / tau)
            let remaining = note.dur - t
            if remaining < release { env *= Swift.max(0, remaining / release) }

            var sample: Double
            switch voice {
            case .glass:
                sample = sin(phase) + 0.32 * exp(-t / (tau * 0.22)) * sin(partialPhase)
                partialPhase += twoPi * freq * 2.76 / sr
                if partialPhase >= twoPi { partialPhase -= twoPi }
            case .soft:
                sample = sin(phase) + 0.06 * sin(2 * phase) + 0.22 * exp(-t / 0.004) * sin(3 * phase)
            case .chip:
                sample = phase < Double.pi ? 0.6 : -0.6
                env = (env * 12).rounded() / 12
            }

            if note.noise > 0 {
                // xorshift32
                rng ^= rng << 13
                rng ^= rng >> 17
                rng ^= rng << 5
                let white = Double(rng) / Double(UInt32.max) * 2 - 1
                let burst = exp(-t / 0.025) // el soplo es un golpe corto al principio
                switch voice {
                case .chip:
                    if i % 6 == 0 { held = white > 0 ? 0.6 : -0.6 }
                    sample += note.noise * burst * held * 1.4
                default:
                    lowpassed += 0.35 * (white - lowpassed)
                    sample += note.noise * burst * lowpassed * 2.2
                }
            }
            out[index] += sample * env * note.amp

            phase += twoPi * freq / sr
            if phase >= twoPi { phase -= twoPi }
        }
    }
}
