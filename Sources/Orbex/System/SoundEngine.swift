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
        let sound: OrbexSound
    }

    private static let sampleRate: Double = 44_100
    private static let poolSize = 6
    private static let idlePauseSeconds: Double = 12
    /// Bajada de volumen mientras suena música.
    private static let duckFactor = 0.45

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isSetUp = false
    private var retryAfter: TimeInterval = 0
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [OrbexSound: TimeInterval] = [:]
    private var idleWork: DispatchWorkItem?
    private var configObserver: NSObjectProtocol?

    private init() {}

    // MARK: - API

    /// Reproduce un sonido respetando volumen, horario silencioso, silencios por evento y ducking.
    func play(_ s: OrbexSound) {
        let model = AppModel.shared
        let settings = model.settings
        guard !settings.mutedSounds.contains(s.rawValue) else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        var volume = settings.effectiveVolume(hour: hour)
        if model.isPlayingMusic && settings.duckWithMusic { volume *= Self.duckFactor }
        volume *= SoundSynth.gain(for: s)
        guard volume > 0.001 else { return }

        // Evitar ráfagas del mismo sonido (p. ej. muchos "tic" en el mismo instante).
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[s], now - last < 0.035 { return }
        lastPlayed[s] = now

        schedule(s, theme: settings.theme, volume: volume)
    }

    /// Vista previa desde Configuración: suena aunque el evento esté silenciado o sea horario silencioso.
    func preview(_ s: OrbexSound, theme: ThemeID) {
        let volume = min(1, max(0, AppModel.shared.settings.volume)) * SoundSynth.gain(for: s)
        guard volume > 0.001 else { return }
        schedule(s, theme: theme, volume: volume)
    }

    /// Prepara los buffers de un tema (sin tocar el hardware de audio) para que el primer sonido salga al toque.
    func preload(theme: ThemeID? = nil) {
        let t = theme ?? AppModel.shared.settings.theme
        for s in OrbexSound.allCases {
            _ = buffer(for: s, theme: t)
        }
    }

    // MARK: - Reproducción

    private func schedule(_ s: OrbexSound, theme: ThemeID, volume: Double) {
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

    private func buffer(for s: OrbexSound, theme: ThemeID) -> AVAudioPCMBuffer? {
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

/// Una nota: frecuencia (Hz), inicio y duración (s), amplitud relativa y glissando opcional hasta otra nota.
struct SynthNote {
    var freq: Double
    var start: Double
    var dur: Double
    var amp: Double
    var glideTo: Double?
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
                          glide: Double? = nil) -> SynthNote {
        SynthNote(freq: freq, start: start, dur: dur, amp: amp, glideTo: glide)
    }

    /// Volumen relativo de cada evento (los frecuentes, más bajitos).
    static func gain(for s: OrbexSound) -> Double {
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

    /// Partitura de cada sonido (0,05–0,9 s).
    static func notes(for s: OrbexSound) -> [SynthNote] {
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

    /// Renderiza un sonido a muestras mono (float, −1…1).
    static func render(_ s: OrbexSound, voice: Voice, sampleRate: Double) -> [Float] {
        let list = notes(for: s)
        let total = list.map { $0.start + $0.dur }.max() ?? 0
        guard total > 0, sampleRate > 0 else { return [] }
        var out = [Double](repeating: 0, count: max(1, Int((total + 0.005) * sampleRate)))
        for note in list {
            add(note, voice: voice, sampleRate: sampleRate, into: &out)
        }
        let peak = out.reduce(0) { Swift.max($0, abs($1)) }
        guard peak > 0 else { return [] }
        let gain = voice.peak / peak
        return out.map { Float($0 * gain) }
    }

    private static func add(_ note: SynthNote, voice: Voice, sampleRate sr: Double, into out: inout [Double]) {
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

        for i in 0..<count {
            let index = startIndex + i
            if index >= out.count { break }
            let t = Double(i) / sr
            var freq = note.freq
            if let ratio {
                freq = note.freq * pow(ratio, t / note.dur)
            }

            // Envolvente: ataque lineal, caída exponencial y un soltado cortito para que no haga "clic".
            var env = t < attack ? t / attack : exp(-(t - attack) / tau)
            let remaining = note.dur - t
            if remaining < release { env *= Swift.max(0, remaining / release) }

            let sample: Double
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
            out[index] += sample * env * note.amp

            phase += twoPi * freq / sr
            if phase >= twoPi { phase -= twoPi }
        }
    }
}
