import AVFoundation
import AppKit

/// La voz de Orbi: dice en voz alta lo que responde.
///
/// Motores, en este orden (el preferido en Configuración va primero): Kokoro local → Cartesia (si hay
/// clave) → voz de macOS. Si uno falla, lo que falta decir sigue con el siguiente.
/// Los textos largos se parten en frases: la primera se sintetiza sola para empezar enseguida y la
/// siguiente se prepara mientras suena la anterior.
///
/// Avisa por `NotificationCenter`:
/// - `orbex.voice.speaking` (`object`: `Bool`) al empezar y al terminar de hablar. El reconocimiento de
///   voz lo usa para no escucharse a sí mismo.
/// - `orbex.voice.outLevel` (`object`: `CGFloat` 0…1, ~20 Hz) con el nivel del audio que sale.
@MainActor
final class OrbiVoice: ObservableObject {
    static let shared = OrbiVoice()

    static let speakingNotification = Notification.Name("orbex.voice.speaking")
    static let outLevelNotification = Notification.Name("orbex.voice.outLevel")
    /// `object`: `String` con el motor en uso ("Kokoro · Dora", "Cartesia", "Voz de macOS").
    static let backendNotification = Notification.Name("orbex.voice.backend")
    /// Entrante: `object` `Bool`; mientras sea `true`, Orbi no suena (lo manda el modo inteligente).
    static let muteNotification = Notification.Name("orbex.voice.mute")
    /// Silencio guardado por el modo inteligente.
    static let mutedDefaultsKey = "orbex.smart.orbiMuted"

    @Published private(set) var isSpeaking = false
    /// Motor en uso (o el que se va a usar la próxima vez).
    @Published private(set) var backend: OrbiVoiceBackend = .system {
        didSet { if backend != oldValue { postBackend() } }
    }

    /// Nombre corto del motor para mostrar ("Kokoro · Dora", "Cartesia", "Voz de macOS").
    var backendLabel: String {
        switch backend {
        case .kokoro:
            let id = OrbiVoiceSettings.kokoroVoice
            let name = OrbiVoiceSettings.kokoroVoices.first { $0.id == id }?.name
                .components(separatedBy: " ·").first ?? id
            return "Kokoro · \(name)"
        case .cartesia: return "Cartesia"
        case .system: return "Voz de macOS"
        }
    }

    /// Silenciado desde el modo inteligente (`orbex.voice.mute` o `orbex.smart.orbiMuted`).
    var isMuted: Bool {
        muteOverride ?? UserDefaults.standard.bool(forKey: Self.mutedDefaultsKey)
    }

    private var muteOverride: Bool?
    /// Kokoro instalado con `scripts/instalar-voz.sh`.
    @Published private(set) var kokoroInstalled = false
    /// Último problema de un motor (se muestra en Configuración); `nil` si anduvo bien.
    @Published private(set) var lastProblem: String?

    /// Preferencia `orbex.voiceOut.enabled` (prendida por defecto). Apagarla corta lo que esté diciendo.
    var isEnabled: Bool {
        get { OrbiVoiceSettings.enabled }
        set {
            objectWillChange.send()
            OrbiVoiceSettings.enabled = newValue
            if !newValue { stop() }
        }
    }

    // MARK: Cola

    private struct Job {
        let chunks: [String]
        let completion: (() -> Void)?
    }

    private var jobs: [Job] = []
    private var currentCompletion: (() -> Void)?
    private var runner: Task<Void, Never>?
    /// Cambia en cada `stop()`: lo que venía de antes se da por cancelado.
    private var generation = 0
    private var speakingOffTask: Task<Void, Never>?
    private var kokoroCooldownUntil = Date.distantPast
    private var cartesiaCooldownUntil = Date.distantPast

    // MARK: Reproducción

    private var player: AVAudioPlayer?
    private var playerOK = true
    private let playerDelegate = OrbiVoicePlayerDelegate()
    private let synth = AVSpeechSynthesizer()
    private let synthDelegate = OrbiVoiceSynthDelegate()
    private var lastUtterance: ObjectIdentifier?
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    // MARK: Nivel

    private var meterTimer: Timer?
    private var level: CGFloat = 0
    private var systemPulse: CGFloat = 0
    private var meterPhase: Double = 0

    private init() {
        synth.delegate = synthDelegate
        refreshAvailability()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            KokoroEngine.shared.shutdownNow()
        }
        NotificationCenter.default.addObserver(forName: Self.muteNotification, object: nil, queue: .main) { note in
            let on = (note.object as? Bool) ?? (note.object as? NSNumber)?.boolValue ?? false
            MainActor.assumeIsolated { OrbiVoice.shared.setMuted(on) }
        }
    }

    // MARK: - API

    /// Dice `text` (se limpia de markdown, código y emoji). `interrupt` corta lo que esté diciendo;
    /// si no, se encola. `completion` se llama una vez, al terminar o si se interrumpe.
    func speak(_ text: String, interrupt: Bool = true, completion: (() -> Void)? = nil) {
        guard isEnabled, !isMuted else { completion?(); return }
        let chunks = SpeechText.chunks(SpeechText.clean(text))
        guard !chunks.isEmpty else { completion?(); return }
        if interrupt { stop() }
        jobs.append(Job(chunks: chunks, completion: completion))
        startRunnerIfNeeded()
    }

    /// Calla a Orbi y vacía la cola.
    func stop() {
        generation += 1
        runner?.cancel()
        runner = nil
        let pending = jobs
        jobs.removeAll()
        haltPlayback()
        let current = currentCompletion
        currentCompletion = nil
        current?()
        pending.forEach { $0.completion?() }
        setSpeaking(false)
    }

    /// Arranca el helper de Kokoro de antemano (por ejemplo, al empezar a escuchar un pedido).
    func prewarm() {
        if backendChain().first == .kokoro {
            KokoroEngine.shared.prewarm(voice: OrbiVoiceSettings.kokoroVoice)
        }
    }

    /// Vuelve a mirar qué motores hay (después de instalar Kokoro, cargar la clave o cambiar ajustes).
    func refreshAvailability() {
        kokoroInstalled = OrbiVoicePaths.kokoroInstalled
        kokoroCooldownUntil = .distantPast
        cartesiaCooldownUntil = .distantPast
        if !isSpeaking { backend = backendChain().first ?? .system }
        postBackend()
    }

    private func setMuted(_ on: Bool) {
        muteOverride = on
        if on { stop() }
    }

    private func postBackend() {
        NotificationCenter.default.post(name: Self.backendNotification, object: backendLabel)
    }

    // MARK: - Motores

    private func isAvailable(_ b: OrbiVoiceBackend) -> Bool {
        switch b {
        case .kokoro: return kokoroInstalled && Date() >= kokoroCooldownUntil
        case .cartesia: return CartesiaClient.isConfigured && Date() >= cartesiaCooldownUntil
        case .system: return true
        }
    }

    private func backendChain() -> [OrbiVoiceBackend] {
        var order: [OrbiVoiceBackend] = [.kokoro, .cartesia, .system]
        if let preferred = OrbiVoiceSettings.preferredBackend {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        return order.filter(isAvailable)
    }

    private func noteFailure(_ b: OrbiVoiceBackend, _ error: Error) {
        let why = error.localizedDescription
        NSLog("ORBEX voz: \(b.rawValue) falló: \(why)")
        lastProblem = "\(b.title): \(why)"
        switch b {
        case .kokoro: kokoroCooldownUntil = Date().addingTimeInterval(120)
        case .cartesia: cartesiaCooldownUntil = Date().addingTimeInterval(60)
        case .system: break
        }
    }

    // MARK: - Cola

    private func startRunnerIfNeeded() {
        guard runner == nil else { return }
        let gen = generation
        setSpeaking(true)
        runner = Task { @MainActor [weak self] in
            await self?.runLoop(gen)
        }
    }

    private func runLoop(_ gen: Int) async {
        while gen == generation, !jobs.isEmpty {
            let job = jobs.removeFirst()
            currentCompletion = job.completion
            await say(job.chunks[...], gen: gen)
            guard gen == generation else { return }
            let done = currentCompletion
            currentCompletion = nil
            done?()
        }
        guard gen == generation else { return }
        runner = nil
        setSpeaking(false)
    }

    private func say(_ chunks: ArraySlice<String>, gen: Int) async {
        var remaining = chunks
        for b in backendChain() {
            guard !remaining.isEmpty, gen == generation else { return }
            backend = b
            switch b {
            case .system:
                await speakSystem(remaining, gen: gen)
                remaining = []
            case .kokoro, .cartesia:
                remaining = await speakAudio(remaining, with: b, gen: gen)
            }
        }
    }

    /// Kokoro o Cartesia. Devuelve lo que no se pudo decir (vacío si anduvo todo).
    private func speakAudio(_ chunks: ArraySlice<String>, with b: OrbiVoiceBackend,
                            gen: Int) async -> ArraySlice<String> {
        let speed = OrbiVoiceSettings.speed
        let kokoroVoice = OrbiVoiceSettings.kokoroVoice
        let cartesiaVoice = OrbiVoiceSettings.cartesiaVoice

        func fetch(_ text: String) -> Task<Result<Data, Error>, Never> {
            Task {
                do {
                    switch b {
                    case .kokoro:
                        return .success(try await KokoroEngine.shared.synthesize(text, voice: kokoroVoice, speed: speed))
                    default:
                        return .success(try await CartesiaClient.synthesize(text, voiceID: cartesiaVoice, speed: speed))
                    }
                } catch {
                    return .failure(error)
                }
            }
        }

        var index = chunks.startIndex
        var next: Task<Result<Data, Error>, Never>? = fetch(chunks[index])
        while index < chunks.endIndex {
            guard let pending = next else { break }
            let result = await pending.value
            guard gen == generation else { return [] }
            let following = chunks.index(after: index)
            next = following < chunks.endIndex ? fetch(chunks[following]) : nil
            switch result {
            case .failure(let error):
                next?.cancel()
                noteFailure(b, error)
                return chunks[index...]
            case .success(let data):
                let ok = await play(data, gen: gen)
                guard gen == generation else { next?.cancel(); return [] }
                if !ok {
                    next?.cancel()
                    noteFailure(b, NSError(domain: "ORBEX", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: "no se pudo reproducir el audio"]))
                    return chunks[index...]
                }
            }
            index = following
        }
        lastProblem = nil
        return []
    }

    private func play(_ data: Data, gen: Int) async -> Bool {
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        p.isMeteringEnabled = true
        p.delegate = playerDelegate
        p.prepareToPlay()
        guard p.play() else { return false }
        player = p
        playerOK = true
        startMeter()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
        }
        if player === p { player = nil }
        return gen != generation || playerOK
    }

    /// Voz de macOS: encola todas las frases en el sintetizador y espera a la última.
    private func speakSystem(_ chunks: ArraySlice<String>, gen: Int) async {
        let voice = SystemVoicePicker.voice(preferred: OrbiVoiceSettings.systemVoice)
        let rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(OrbiVoiceSettings.speed),
                           AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        var last: AVSpeechUtterance?
        for text in chunks {
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            u.rate = rate
            u.pitchMultiplier = 1.05
            u.postUtteranceDelay = 0.04
            synth.speak(u)
            last = u
        }
        guard let last else { return }
        lastUtterance = ObjectIdentifier(last)
        startMeter()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
        }
        lastUtterance = nil
    }

    private func haltPlayback() {
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        lastUtterance = nil
        resumePlayback()
    }

    private func resumePlayback() {
        let cont = playbackContinuation
        playbackContinuation = nil
        cont?.resume()
    }

    // MARK: - Callbacks de los delegados

    fileprivate func playerFinished(_ id: ObjectIdentifier, ok: Bool) {
        guard let player, ObjectIdentifier(player) == id else { return }
        playerOK = ok
        resumePlayback()
    }

    fileprivate func utteranceFinished(_ id: ObjectIdentifier, cancelled: Bool) {
        guard id == lastUtterance else { return }
        resumePlayback()
    }

    fileprivate func systemWordSpoken() {
        systemPulse = CGFloat.random(in: 0.55...1.0)
    }

    // MARK: - Estado y nivel

    private func setSpeaking(_ on: Bool) {
        speakingOffTask?.cancel()
        speakingOffTask = nil
        if on {
            guard !isSpeaking else { return }
            isSpeaking = true
            NotificationCenter.default.post(name: Self.speakingNotification, object: true)
        } else {
            guard isSpeaking else { return }
            // Un respiro antes de avisar: que el eco del parlante no entre al micrófono.
            speakingOffTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled, self.runner == nil else { return }
                self.isSpeaking = false
                self.stopMeter()
                if let b = self.backendChain().first { self.backend = b }
                NotificationCenter.default.post(name: Self.speakingNotification, object: false)
            }
        }
    }

    private func startMeter() {
        guard meterTimer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { OrbiVoice.shared.tickMeter() }
        }
        RunLoop.main.add(t, forMode: .common)
        meterTimer = t
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
        systemPulse = 0
        NotificationCenter.default.post(name: Self.outLevelNotification, object: CGFloat(0))
    }

    private func tickMeter() {
        var target: CGFloat = 0
        if let p = player, p.isPlaying {
            p.updateMeters()
            let channels = max(p.numberOfChannels, 1)
            var avg: Float = -160, peak: Float = -160
            for c in 0..<channels {
                avg = max(avg, p.averagePower(forChannel: c))
                peak = max(peak, p.peakPower(forChannel: c))
            }
            let a = CGFloat((avg + 48) / 42)
            let pk = CGFloat((peak + 48) / 48)
            target = min(max(a * 0.75 + pk * 0.25, 0), 1)
        } else if synth.isSpeaking {
            // La voz de macOS no da el nivel: se simula con cada palabra y un vaivén suave.
            meterPhase += 0.05 * 9
            systemPulse *= 0.84
            target = min(0.18 + systemPulse * 0.7 + CGFloat(sin(meterPhase)) * 0.06, 1)
        }
        let k: CGFloat = target > level ? 0.6 : 0.28   // sube rápido, baja suave
        level += (target - level) * k
        NotificationCenter.default.post(name: Self.outLevelNotification, object: level)
    }
}

// MARK: - Delegados (los callbacks pueden llegar fuera del hilo principal)

private final class OrbiVoicePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in OrbiVoice.shared.playerFinished(id, ok: flag) }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in OrbiVoice.shared.playerFinished(id, ok: false) }
    }
}

private final class OrbiVoiceSynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in OrbiVoice.shared.utteranceFinished(id, cancelled: false) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in OrbiVoice.shared.utteranceFinished(id, cancelled: true) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        Task { @MainActor in OrbiVoice.shared.systemWordSpoken() }
    }
}
